/// The only barangays WackySmart delivers to. Kept in one place so the
/// customer address form and the admin delivery-schedule routing logic
/// can never disagree about what counts as a serviceable area.
///
/// Tungawan is the full base-of-operations municipality. R.T. Lim and
/// Ipil are limited to their town center plus the barangays along the
/// Tungawan-Ipil highway corridor - remote/upland barangays too hard
/// for an L300 truck to reach are intentionally excluded.
library service_areas;

const List<String> tungawanBarangays = [
  'Baluran',
  'Batungan',
  'Cayamcam',
  'Datu Tumanggong',
  'Gaycon',
  'Langon',
  'Libertad (Poblacion)',
  'Linguisan',
  'Little Margos',
  'Loboc',
  'Looc-labuan',
  'Lower Tungawan',
  'Masao',
  'San Isidro',
  'San Pedro',
  'San Vicente',
  'Santo Niño',
  'Sisay',
  'Taglibas',
  'Tigbanuang',
  'Tigbucay',
  'Tigpalay',
  'Timbabauan',
  'Tobu-Tubo',
  'Upper Tungawan',
];

const List<String> rtLimBarangays = [
  'Pres. Roxas (Poblacion)',
  'Don Perfecto',
  'Katipunan',
  'Ali Alsree',
  'San Fernandino',
  'Malubal',
  'Santo Rosario',
  'Silingan',
  'Surabay',
  'San Antonio',
  'Siawang',
  'Magsaysay',
];

const List<String> ipilBarangays = [
  'Poblacion',
  'Ipil Heights',
  'Lower Ipil Heights',
  'Sanito',
  'Suclema',
  'Bangkerohan',
  'Bacalan',
  'Bulu-an',
  'Caparan',
  'Taway',
  'Lower Taway',
  'Tenan',
];

/// Flat, dropdown-ready list: "<Barangay>, <Municipality>" so areas with
/// the same barangay name in different towns never collide.
final List<String> serviceableAreas = [
  for (final b in tungawanBarangays) '$b, Tungawan',
  for (final b in rtLimBarangays) '$b, R.T. Lim',
  for (final b in ipilBarangays) '$b, Ipil',
];
