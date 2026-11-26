// supabase/functions/kyc-verify/index.ts
//
// Compares the user's selfies to the photo on their ID using AWS Rekognition
// and updates public.kyc_submissions with a status + similarity score.
//
// Secrets required (supabase secrets set ...):
//   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION (e.g. ap-southeast-1)
// Optional:
//   KYC_AUTO_APPROVE (default 95), KYC_MANUAL_REVIEW (default 80)

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  CompareFacesCommand,
  RekognitionClient,
} from "npm:@aws-sdk/client-rekognition@3";

const BUCKET = "kyc-documents";
const AUTO_APPROVE = Number(Deno.env.get("KYC_AUTO_APPROVE") ?? "95");
const MANUAL_REVIEW = Number(Deno.env.get("KYC_MANUAL_REVIEW") ?? "80");
const SELFIE_CONSISTENCY = 90; // neutral vs smile selfie must be the same person

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const rekognition = new RekognitionClient({
  region: Deno.env.get("AWS_REGION") ?? "ap-southeast-1",
  credentials: {
    accessKeyId: Deno.env.get("AWS_ACCESS_KEY_ID")!,
    secretAccessKey: Deno.env.get("AWS_SECRET_ACCESS_KEY")!,
  },
});

/** Returns similarity 0-100 of the largest face in `source` vs faces in `target`. */
async function compare(source: Uint8Array, target: Uint8Array): Promise<number> {
  try {
    const res = await rekognition.send(
      new CompareFacesCommand({
        SourceImage: { Bytes: source },
        TargetImage: { Bytes: target },
        SimilarityThreshold: 0, // return every match so we always get a score
        QualityFilter: "AUTO",
      }),
    );
    const best = Math.max(0, ...(res.FaceMatches ?? []).map((m) => m.Similarity ?? 0));
    return best;
  } catch (e) {
    // InvalidParameterException = no face found in one of the images
    if ((e as { name?: string }).name === "InvalidParameterException") return 0;
    throw e;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Unauthorized" }, 401);

    // 1. Identify the caller from their JWT (never trust a userId from the body)
    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    if (userErr || !user) return json({ error: "Unauthorized" }, 401);

    // 2. Admin client (bypasses RLS) for storage + status updates
    const admin = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: sub, error: subErr } = await admin
      .from("kyc_submissions")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();

    if (subErr) throw subErr;
    if (!sub) return json({ error: "No KYC submission found" }, 404);

    // Don't re-run on already-decided submissions (prevents retry abuse / cost)
    if (sub.status !== "pending" || sub.face_match_score !== null) {
      return json({ status: sub.status, score: sub.face_match_score });
    }

    // 3. Download the three images
    const download = async (path: string) => {
      const { data, error } = await admin.storage.from(BUCKET).download(path);
      if (error || !data) throw new Error(`Download failed: ${path}`);
      return new Uint8Array(await data.arrayBuffer());
    };

    const [idImg, selfie, smile] = await Promise.all([
      download(sub.id_image_path),
      download(sub.selfie_path),
      download(sub.selfie_smile_path),
    ]);

    // 4. Compare
    const [selfieVsId, smileVsId, selfieVsSmile] = await Promise.all([
      compare(selfie, idImg),
      compare(smile, idImg),
      compare(selfie, smile),
    ]);

    const score = Math.min(selfieVsId, smileVsId);

    // 5. Decide
    let status: "approved" | "pending" | "rejected";
    let note: string;

    if (selfieVsSmile < SELFIE_CONSISTENCY) {
      status = "rejected";
      note = `Selfies do not appear to be the same person (${selfieVsSmile.toFixed(1)}).`;
    } else if (score >= AUTO_APPROVE) {
      status = "approved";
      note = "Auto-approved by face match.";
    } else if (score >= MANUAL_REVIEW) {
      status = "pending"; // borderline: leave for a human admin
      note = "Borderline face match: needs manual review.";
    } else {
      status = "rejected";
      note = "Face on ID does not match the selfies.";
    }

    const { error: updErr } = await admin
      .from("kyc_submissions")
      .update({
        status,
        face_match_score: Number(score.toFixed(2)),
        review_note: note,
        reviewed_at: status === "pending" ? null : new Date().toISOString(),
      })
      .eq("user_id", user.id);

    if (updErr) throw updErr;

    return json({ status, score: Number(score.toFixed(2)) });
  } catch (e) {
    console.error("kyc-verify error:", e);
    return json({ error: "Verification failed. Please try again later." }, 500);
  }
});
