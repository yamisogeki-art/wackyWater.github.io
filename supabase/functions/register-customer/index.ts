// supabase/functions/register-customer/index.ts
//
// Creates a customer account ONLY if the neutral selfie, the smiling selfie and
// the photo on the ID all show the same person (AWS Rekognition CompareFaces).
//
// Secrets required: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION
// Optional:         KYC_MIN_ID_MATCH (default 85), KYC_MIN_SELFIE_MATCH (default 90)

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  CompareFacesCommand,
  RekognitionClient,
} from "npm:@aws-sdk/client-rekognition@3";

const BUCKET = "kyc-documents";
const MIN_ID_MATCH = Number(Deno.env.get("KYC_MIN_ID_MATCH") ?? "85");
const MIN_SELFIE_MATCH = Number(Deno.env.get("KYC_MIN_SELFIE_MATCH") ?? "90");
const MAX_ATTEMPTS_PER_HOUR = 10;
const MAX_B64_LENGTH = 7_000_000; // about 5 MB per image (Rekognition's limit)

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

function toBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const awsKey = Deno.env.get("AWS_ACCESS_KEY_ID");
  const awsSecret = Deno.env.get("AWS_SECRET_ACCESS_KEY");
  if (!awsKey || !awsSecret) {
    console.error("AWS credentials are not configured");
    return json(
      { error: "Face verification is not available right now. Please try again later." },
      503,
    );
  }

  // 1. Read and validate the input
  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request." }, 400);
  }

  const fullName = String(body.full_name ?? "").trim();
  const email = String(body.email ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  const idType = String(body.id_type ?? "").trim();
  const idB64 = String(body.id_image ?? "");
  const selfieB64 = String(body.selfie ?? "");
  const smileB64 = String(body.selfie_smile ?? "");

  if (!fullName) return json({ error: "Please enter your full name." }, 400);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return json({ error: "Please enter a valid email address." }, 400);
  }
  if (password.length < 8) {
    return json({ error: "Password must be at least 8 characters." }, 400);
  }
  if (!idType) return json({ error: "Please choose your ID type." }, 400);
  if (!idB64 || !selfieB64 || !smileB64) {
    return json({ error: "Please add your ID and both face photos." }, 400);
  }
  if ([idB64, selfieB64, smileB64].some((s) => s.length > MAX_B64_LENGTH)) {
    return json({ error: "One of the photos is too large. Please retake it." }, 400);
  }

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 2. Limit attempts per IP address (each attempt costs 3 face comparisons)
    const ip = (req.headers.get("x-forwarded-for") ?? "unknown").split(",")[0].trim();
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count, error: countErr } = await admin
      .from("registration_attempts")
      .select("id", { count: "exact", head: true })
      .eq("ip", ip)
      .gte("created_at", since);
    if (countErr) console.error("attempt count failed:", countErr.message);
    if ((count ?? 0) >= MAX_ATTEMPTS_PER_HOUR) {
      return json({ error: "Too many attempts. Please try again in an hour." }, 429);
    }
    await admin.from("registration_attempts").insert({ ip, email });

    // 3. Compare the three photos
    const rekognition = new RekognitionClient({
      region: Deno.env.get("AWS_REGION") ?? "ap-southeast-1",
      credentials: { accessKeyId: awsKey, secretAccessKey: awsSecret },
    });

    const compare = async (source: Uint8Array, target: Uint8Array): Promise<number> => {
      try {
        const res = await rekognition.send(
          new CompareFacesCommand({
            SourceImage: { Bytes: source },
            TargetImage: { Bytes: target },
            SimilarityThreshold: 0,
            QualityFilter: "AUTO",
          }),
        );
        return Math.max(0, ...(res.FaceMatches ?? []).map((m) => m.Similarity ?? 0));
      } catch (e) {
        // InvalidParameterException = no face found in one of the images
        if ((e as { name?: string }).name === "InvalidParameterException") return 0;
        throw e;
      }
    };

    const idBytes = toBytes(idB64);
    const selfieBytes = toBytes(selfieB64);
    const smileBytes = toBytes(smileB64);

    const [selfieVsId, smileVsId, selfieVsSmile] = await Promise.all([
      compare(selfieBytes, idBytes),
      compare(smileBytes, idBytes),
      compare(selfieBytes, smileBytes),
    ]);
    console.log("register-customer scores", { selfieVsId, smileVsId, selfieVsSmile });

    if (selfieVsSmile < MIN_SELFIE_MATCH) {
      return json({
        error: "The two selfies do not look like the same person. Please retake both in good light.",
      }, 422);
    }
    if (selfieVsId < MIN_ID_MATCH || smileVsId < MIN_ID_MATCH) {
      return json({
        error:
          "Your face does not match the photo on your ID. Retake your photos in good light and make sure the whole ID is visible.",
      }, 422);
    }

    // 4. All three match: create the account (no confirmation email needed)
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName, role: "customer" },
    });
    if (createErr || !created?.user) {
      const msg = createErr?.message ?? "";
      if (/already|registered|exists/i.test(msg)) {
        return json({ error: "An account with this email already exists. Please log in." }, 409);
      }
      console.error("createUser failed:", msg);
      return json({ error: "Could not create your account. Please try again." }, 500);
    }
    const uid = created.user.id;

    // 5. Keep the photos and the result on file
    try {
      const upload = async (name: string, bytes: Uint8Array) => {
        const path = `${uid}/${name}.jpg`;
        const { error } = await admin.storage
          .from(BUCKET)
          .upload(path, bytes, { contentType: "image/jpeg", upsert: true });
        if (error) throw error;
        return path;
      };
      const [idPath, selfiePath, smilePath] = await Promise.all([
        upload("id", idBytes),
        upload("selfie", selfieBytes),
        upload("selfie_smile", smileBytes),
      ]);

      const { error: rowErr } = await admin.from("kyc_submissions").upsert({
        user_id: uid,
        id_type: idType,
        id_image_path: idPath,
        selfie_path: selfiePath,
        selfie_smile_path: smilePath,
        status: "approved",
        face_match_score: Number(Math.min(selfieVsId, smileVsId).toFixed(2)),
        review_note: "Faces matched at registration.",
        reviewed_at: new Date().toISOString(),
      });
      if (rowErr) throw rowErr;
    } catch (e) {
      console.error("saving verification failed:", e);
      await admin.auth.admin.deleteUser(uid); // roll back so the user can try again
      return json({ error: "Could not save your verification. Please try again." }, 500);
    }

    return json({ ok: true });
  } catch (e) {
    console.error("register-customer error:", e);
    return json({ error: "Verification failed. Please try again later." }, 500);
  }
});
