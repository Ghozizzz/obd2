/// Fuel-economy math derived from MAF.
///
/// fuel mass flow = MAF / AFR        (g/s of fuel)
/// fuel vol flow  = mass / density   (L/s) -> *3600 -> L/h
/// economy        = speed / (L/h)    (km per L)
class FuelCalc {
  static const double afr = 14.7;       // gasoline stoichiometric ratio
  static const double density = 745.0;  // g/L, typical gasoline

  // Speed-density constants for Nissan QR25DE (X-Trail T31 2.5L).
  static const double displacementL = 2.488; // engine displacement, L
  static const double ve = 0.85;             // volumetric efficiency estimate
  static const double molarMassAir = 28.97;  // g/mol
  static const double rGas = 8.314;          // J/(mol·K)

  /// Liters per hour from MAF (g/s).
  static double litersPerHour(double mafGs) =>
      mafGs * 3600.0 / (afr * density);

  /// Speed-density airflow estimate (g/s) when the ECU has no MAF sensor.
  /// Derived from ideal gas law for a 4-stroke (two revs per intake cycle):
  ///   air mass/cycle = (MAP * VE * disp * MM_air) / (R * IAT_K)
  ///   cycles/sec     = RPM / 60 / 2
  /// → g/s = MAP_Pa * VE * disp_m3 * MM_air * RPM / (R * IAT_K * 120)
  static double mafFromSpeedDensity({
    required int mapKpa,
    required int rpm,
    required int iatC,
  }) {
    final iatK = iatC + 273.15;
    final mapPa = mapKpa * 1000.0;
    final dispM3 = displacementL / 1000.0; // L → m³
    if (iatK <= 0 || rpm <= 0) return 0.0;
    return mapPa * ve * dispM3 * molarMassAir * rpm /
        (rGas * iatK * 120.0);
  }

  /// Instantaneous km/L. At standstill (speed 0) economy is undefined → 0.0
  /// so the HUD shows "0.0" rather than infinity while idling.
  static double kmPerLiter(double mafGs, int speedKmh) {
    if (speedKmh <= 0) return 0.0;
    final lph = litersPerHour(mafGs);
    if (lph <= 0) return 0.0;
    return speedKmh / lph;
  }
}
