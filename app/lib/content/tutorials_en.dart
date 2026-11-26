part of 'tutorials.dart';

const _englishTutorials = <String, Tutorial>{
  'tin': Tutorial(
    title: 'TIN earthwork volumes',
    summary:
        'Estimate earthwork from an existing triangular mesh and a horizontal design elevation.',
    formulas: ['ΔHᵢ = Hᵢ − Hdesign', 'V = A × (ΔH₁ + ΔH₂ + ΔH₃) / 3'],
    steps: [
      'Enter one X,Y,H point per line, in metres.',
      'Enter three one-based point indices per triangle.',
      'Enter the design elevation and calculate the plan area, cut, fill and net volume.'
    ],
    example: [
      ('Points', '(0,0,12) / (10,0,12) / (0,10,12)'),
      ('Triangle / design elevation', '1,2,3 / 10 m'),
      ('Area / cut', '50 m² / 100 m³')
    ],
    notes: [
      'Each triangle is classified by its signed volume. A triangle crossing the design plane contributes its net volume.'
    ],
  ),
  'inverse': Tutorial(
    title: 'Coordinate inverse',
    summary:
        'Find the horizontal distance and azimuth between two known points.',
    formulas: [
      'ΔN = NB − NA; ΔE = EB − EA',
      'D = √(ΔN² + ΔE²)',
      'α = atan2(ΔE, ΔN), wrapped to [0°, 360°)'
    ],
    steps: [
      'Enter the northing (X) and easting (Y) of both points.',
      'Compare the result to the plotted direction, or use Export to save the table.'
    ],
    example: [
      ('A → B', '(1000, 2000) → (1080, 2060)'),
      ('D / α', '100.000 m / 36°52′11.6″')
    ],
    notes: [
      'Azimuth is measured clockwise from north. Coincident points give a zero distance and no geometric direction.'
    ],
  ),
  'polar': Tutorial(
    title: 'Coordinate forward calculation',
    summary:
        'Find a target coordinate from a known station, a north-referenced azimuth and a horizontal distance.',
    formulas: ['NB = NA + D·cos α', 'EB = EA + D·sin α'],
    steps: [
      'Enter the station coordinates, azimuth and horizontal distance.',
      'Read the target coordinates or inspect the ray on the plot.'
    ],
    example: [
      ('Station', 'N = 1000 m; E = 2000 m'),
      ('Azimuth / distance', '36°52′11.6″ / 50 m'),
      ('Target', 'N ≈ 1040 m; E ≈ 2030 m')
    ],
    notes: [
      'Choose DMS, DD or RAD for angle entry. Use the Setting-out data tool for relative angles from a backsight.'
    ],
  ),
  'stakeout': Tutorial(
    title: 'Setting-out data',
    summary:
        'Calculate the clockwise turn from a backsight to a target and the horizontal distance from the occupied station.',
    formulas: ['β = (αtarget − αbacksight) mod 360°', 'D = √(ΔN² + ΔE²)'],
    steps: [
      'Enter the occupied station and the known backsight.',
      'Enter the target and calculate its turn and distance.'
    ],
    example: [
      ('Station / backsight', '(1000, 2000) / (1100, 2000)'),
      ('Target', '(1040, 2030)'),
      ('β / D', '36°52′11.6″ / 50.000 m')
    ],
    notes: [
      'The distance is horizontal. A slope distance requires an additional vertical observation.'
    ],
  ),
  'batch_stakeout': Tutorial(
    title: 'Batch setting out',
    summary:
        'Compute turns and horizontal distances to several targets from one station and backsight.',
    formulas: ['βᵢ = (αᵢ − αbacksight) mod 360°', 'Dᵢ = √(ΔNᵢ² + ΔEᵢ²)'],
    steps: [
      'Enter the station and backsight once.',
      'Enter each target as point ID, northing and easting.',
      'Select a result row or plot point, then copy CSV or export the result.'
    ],
    example: [
      ('Station / backsight', '(1000, 2000) / (1100, 2000)'),
      ('Target', 'P1, 1040, 2030'),
      ('P1', '36°52′11.6″ / 50.000 m')
    ],
    notes: [
      'A target that coincides with the station is flagged. Other targets are still calculated.'
    ],
  ),
  'resection': Tutorial(
    title: 'Three-point angular resection',
    summary:
        'Determine an unknown station from clockwise turns to three known control points.',
    formulas: [
      'The observed chords AB and BC define two circles through B and the unknown station P.'
    ],
    steps: [
      'Enter the coordinates of A, B and C in observation order.',
      'At P, enter the clockwise angles A→B and B→C.'
    ],
    example: [
      ('A / B / C', '(100, 0) / (120, 120) / (0, 100)'),
      ('Turns / P', '45° / 45° → (0, 0)')
    ],
    notes: [
      'Coincident circles form the danger circle. It does not determine a unique station.'
    ],
  ),
  'intersection': Tutorial(
    title: 'Forward intersection',
    summary:
        'Determine P from the two known stations A and B and the angles read at those stations.',
    formulas: [
      'γ = 180° − α − β',
      'Np = (Na·tan α + Nb·tan β + (Eb−Ea)·tan α·tan β) / (tan α + tan β)',
      'Ep = (Ea·tan α + Eb·tan β + (Na−Nb)·tan α·tan β) / (tan α + tan β)',
    ],
    steps: [
      'Enter the coordinates of A and B.',
      'Enter ∠BAP at A and ∠ABP at B. Review the intermediate values and plotted solution.'
    ],
    example: [
      ('A / B', '(659.232, 355.537) / (406.593, 654.051)'),
      ('α / β', '69°11′03″ / 59°42′39″'),
      ('P', '(869.198, 735.228)')
    ],
    notes: [
      'A shallow intersection angle makes position sensitive to angular errors. Distance intersection uses AP and BP when those distances are available.'
    ],
  ),
  'traverse': Tutorial(
    title: 'Traverse adjustment',
    summary:
        'Adjust angles and coordinates for a closed loop or a connecting traverse between known controls.',
    formulas: [
      'fβ = Σβobserved − Σβtheoretical',
      'fx = ΣΔN − (Nend − Nstart)',
      'fy = ΣΔE − (Eend − Estart)',
      'f = √(fx² + fy²); 1/K = f / ΣD'
    ],
    steps: [
      'Choose a closed loop or connecting traverse, and choose left or right angles.',
      'Enter the control and azimuth data, then the observed turns and distances.',
      'Review angular and linear misclosure. Choose distribution by leg length or coordinate component.'
    ],
    example: [
      ('Start', 'N = 536.27 m; E = 328.74 m; α = 48°43′18″'),
      ('Angular misclosure', '−60.0″, tolerance ±89.4″'),
      ('Linear misclosure', '0.119 m, approximately 1:4081')
    ],
    notes: [
      'For a closed loop the sum convention depends on whether the observed angles are interior or exterior. Review the detected convention before accepting the result.'
    ],
  ),
  'leveling': Tutorial(
    title: 'Levelling adjustment',
    summary:
        'Adjust observed height differences between known elevations. The dual-face view also reports individual station checks.',
    formulas: [
      'fh = ΣΔH − (Hend − Hstart)',
      'vᵢ = −fh × wᵢ / Σw',
      'ΔHadjusted = ΔH + vᵢ'
    ],
    steps: [
      'Enter the start and end elevations and the observed height differences.',
      'Enter leg lengths or station counts according to the selected weighting.',
      'Review the misclosure, corrections and adjusted elevations.'
    ],
    example: [
      ('Closed loop', 'ΣΔH = +8 mm'),
      ('Total correction', 'Σv = −8 mm')
    ],
    notes: [
      'Use a consistent unit for all weights. Select the project’s tolerance in the route options.'
    ],
  ),
  'precision': Tutorial(
    title: 'Precision assessment',
    summary:
        'Summarise repeat observations or residuals using their mean and sample standard deviation.',
    formulas: ['x̄ = Σxᵢ / n', 's = √[Σ(xᵢ − x̄)² / (n − 1)]'],
    steps: [
      'Enter the observations or residuals using a common unit.',
      'Read the mean, standard deviation and maximum deviation from the mean.'
    ],
    example: [
      ('Observations', '9, 10, 11'),
      ('Mean / standard deviation', '10 / 1')
    ],
    notes: [
      'The displayed sample standard deviation uses at least two observations.'
    ],
  ),
  'circular_curve': Tutorial(
    title: 'Circular-curve elements',
    summary:
        'Calculate tangent length, arc length, external distance and key chainages from deflection angle and radius.',
    formulas: [
      'T = R·tan(α/2)',
      'L = R·α·π/180',
      'E = R·(sec(α/2) − 1)',
      'q = 2T − L'
    ],
    steps: [
      'Enter intersection chainage, deflection angle and radius.',
      'Read the calculated elements and key stations: ZY (PC), QZ (MC), and YZ (PT).'
    ],
    example: [('α / R', '40° / 300 m'), ('T / L', '109.19 m / 209.44 m')],
    notes: [
      'Use the magnitude of the deflection angle in the length formulas. Choose the appropriate side when staking out.'
    ],
  ),
  'clothoid': Tutorial(
    title: 'Clothoid transition',
    summary:
        'Calculate the geometry of a transition between a tangent and a circular arc.',
    formulas: [
      'A = √(R·l)',
      'p ≈ l²/(24R) − l⁴/(2688R³)',
      'm ≈ l/2 − l³/(240R²)',
      'T = (R + p)·tan(α/2) + m'
    ],
    steps: [
      'Enter the radius, transition length and total deflection angle.',
      'Review the shifted alignment, arc length, and key stations: ZH (TS), HY (SC), QZ (MC), YH (CS), and HZ (ST).'
    ],
    example: [('R / l', '300 m / 60 m'), ('p / m', '≈ 0.50 m / 29.99 m')],
    notes: [
      'Check the transition length against the project’s alignment design criteria.'
    ],
  ),
  'vertical_curve': Tutorial(
    title: 'Vertical-curve elements',
    summary:
        'Calculate a parabolic profile between two grades and query the design elevation at a selected chainage.',
    formulas: [
      'ω = i₂ − i₁',
      'L = R·|ω|; T = L/2',
      'H = Hbvc + i₁·x + ω·x²/(2L)'
    ],
    steps: [
      'Enter the intersection chainage and elevation, incoming grade, outgoing grade and radius.',
      'Read the curve elements or enter a chainage to query its design elevation.'
    ],
    example: [
      ('Grades / radius', '+2.0% / −1.5%; R = 5000 m'),
      ('L / T', '175 m / 87.5 m')
    ],
    notes: [
      'Grades are positive in the uphill direction of increasing chainage. Use grade fractions in the formulas.'
    ],
  ),
  'route_stake': Tutorial(
    title: 'Curve staking offsets',
    summary:
        'Calculate local tangent and normal offsets at a selected distance along a circular curve or clothoid.',
    formulas: ['Circular curve: θ = s/R; x = R·sin θ; y = R·(1 − cos θ)'],
    steps: [
      'Choose a circular curve or a clothoid and enter its geometry.',
      'Enter distance along the curve from the start and read the local offsets.'
    ],
    example: [
      ('Circular arc', 'R = 100 m; s = 50 m'),
      ('x / y', '47.943 m / 12.242 m')
    ],
    notes: ['The origin and axes are local to the start of the curve.'],
  ),
  'area': Tutorial(
    title: 'Polygon area',
    summary:
        'Calculate area, perimeter and centroid from the ordered vertices of a boundary.',
    formulas: ['S = ½·|Σ(NᵢEᵢ₊₁ − Nᵢ₊₁Eᵢ)|', 'P = ΣDᵢ'],
    steps: [
      'Enter vertices in boundary order, clockwise or anticlockwise.',
      'Inspect the polygon, then export the area and edge results.'
    ],
    example: [
      ('Vertices', '(0, 0), (100, 0), (100, 50), (0, 50)'),
      ('Area / perimeter', '5000 m² / 300 m')
    ],
    notes: [
      'Use a simple boundary. A self-intersecting polygon does not represent a single parcel.'
    ],
  ),
  'earthwork': Tutorial(
    title: 'Earthwork volumes',
    summary:
        'Estimate cut and fill with a grid, or calculate volume from successive cross-sections.',
    formulas: [
      'Average end area: V = Σ[Dᵢ·(Aᵢ + Aᵢ₊₁)/2]',
      'Grid: Vnet = Vcut − Vfill'
    ],
    steps: [
      'For sections, enter the section areas and intervals.',
      'For a grid, enter the cell size and corner height differences in the sign convention shown by the form.',
      'Review total volumes and any cells split by the zero line.'
    ],
    example: [
      ('Sections', 'A₁ = 10 m²; A₂ = 14 m²; D = 20 m'),
      ('Volume', '240 m³')
    ],
    notes: [
      'Mixed cut and fill within a grid cell are split at the zero line.'
    ],
  ),
  'projection': Tutorial(
    title: 'Coordinate transformations',
    summary:
        'Use Gauss–Krüger projection, planar similarity, geodetic/cartesian conversion or seven-parameter datum transformation.',
    formulas: [
      'Planar similarity: N₂ = dN + k(N₁cos θ − E₁sin θ)',
      'E₂ = dE + k(N₁sin θ + E₁cos θ)'
    ],
    steps: [
      'Choose the method, ellipsoid and coordinate conventions.',
      'For a fit, enter common points and review residuals before applying the transformation.',
      'For projection, review the central meridian and false easting.'
    ],
    example: [
      ('Gauss–Krüger', 'B = 39.9°, L = 116.4°, CGCS2000, 3° zone'),
      (
        'Projected',
        'N ≈ 4418598.001 m; E ≈ 448688.856 m; central meridian 117°'
      )
    ],
    notes: [
      'Document the zone, false easting and rotation convention when exchanging coordinates.'
    ],
  ),
  'leveling4': Tutorial(
    title: 'Fourth-order differential levelling',
    summary:
        'Record dual-face observations, check each station and adjust the route to the known benchmarks.',
    formulas: [
      'Optical stadia: D = 0.1·|upper − lower| with readings in mm and distance in m.',
      'd = Dbacksight − Dforesight; accumulate Σd.',
      'Staff check: K + black − red.',
      'ΔH = [(BSblack − FSblack) + (BSred − FSred) − (KBS − KFS)] / 2.'
    ],
    steps: [
      'Record the black and red backsight faces, then the black and red foresight faces.',
      'Use direct distances in electronic mode. Check staff constants, sight distances and face differences.',
      'Enter the known endpoint elevations and review the route misclosure and corrections.'
    ],
    example: [
      ('Stadia (BS / FS)', '1571/1197 / 1385/998 mm'),
      ('Faces (BS / FS)', '1384/6071 / 1211/5998 mm'),
      ('d / ΔH', '−1.3 m / +173 mm')
    ],
    notes: [
      'Fourth-order checks use a selected 80 m or 100 m sight limit, |d| ≤ 3 m, |Σd| ≤ 10 m with a warning at 7 m, a staff check of 3 mm, and a corrected face difference of 5 mm.',
      'For distance-based route closure, the flat and mountainous options use ±20√L and ±25√L mm respectively, with L in km.'
    ],
  ),
  'quadrant': Tutorial(
    title: 'Azimuth and quadrant bearing',
    summary:
        'Convert a clockwise azimuth from north to a quadrant bearing or back again.',
    formulas: [
      'NE: R = α',
      'SE: R = 180° − α',
      'SW: R = α − 180°',
      'NW: R = 360° − α'
    ],
    steps: [
      'Enter an azimuth, or select the quadrant and enter the bearing angle.'
    ],
    example: [('Azimuth', '123°45′30″'), ('Bearing', 'S 56°14′30″ E')],
    notes: [
      'At a cardinal direction, use the underlying azimuth to distinguish the boundary.'
    ],
  ),
  'convert': Tutorial(
    title: 'Unit conversions',
    summary: 'Convert angles, slope and distance units.',
    formulas: ['1° = 60′ = 3600″ = π/180 rad', 'Slope (%) = 100·tan θ'],
    steps: [
      'Choose a quantity and enter the value in the source unit. The other representations update immediately.'
    ],
    example: [('Angle', '36°52′11.6″ ≈ 36.869889°'), ('Slope', '2% ≈ 1.1458°')],
    notes: [
      'Compact DMS uses degrees followed by minutes and seconds, for example 36.5211 = 36°52′11″.'
    ],
  ),
  'formula': Tutorial(
    title: 'Offline formula calculator',
    summary:
        'Evaluate an expression with named variables or load a formula from the built-in library.',
    formulas: [
      'Operators: + − × ÷ ^',
      'Functions include sin, cos, tan, atan2, sqrt, abs and ln.'
    ],
    steps: [
      'Enter the formula and any variables.',
      'Calculate the result or select a formula from the library.'
    ],
    example: [('Input', '100*sin(36.86989765)'), ('Result', '≈ 60')],
    notes: [
      'Direct trigonometric functions take decimal degrees on this page. Inverse trigonometric functions return radians. Use deg(…) to convert them to degrees.'
    ],
  ),
  'control_points': Tutorial(
    title: 'Control point library',
    summary:
        'Manage persistent project control points (Point ID, Northing X, Easting Y, Elevation H, group, and notes) with CSV/DXF batch import and one-tap picker integration.',
    formulas: [
      'Standard CSV: Name, X (Northing), Y (Easting), H (Elevation), Group, Note',
      'CASS CSV: Name, Code, Y (Easting), X (Northing), H (Elevation)'
    ],
    steps: [
      'Add individual control points or batch-import CSV / DXF coordinate files.',
      'Filter by group or search keyword, with real-time duplicate-name warnings.',
      'Tap "Project to LivePlot" to inspect the control network (North X up, East Y right).',
      'Pick stored control points directly inside inverse, polar, stakeout, intersection, traverse, and levelling tools.'
    ],
    example: [
      ('Control point', 'K1: X=3054120.450, Y=523410.120, H=845.320'),
      ('Export', 'Standard CSV and CASS exchange format')
    ],
    notes: [
      'Surveying convention is enforced throughout: X is Northing and Y is Easting.',
      'CASS files place Easting (Y) before Northing (X); the importer maps columns accordingly.'
    ],
  ),
};
