part of 'tutorials.dart';

const _frenchTutorials = <String, Tutorial>{
  'tin': Tutorial(
    title: 'Cubatures par réseau triangulé',
    summary:
        'Estimer les terrassements à partir d’un maillage triangulaire existant et d’une cote de projet horizontale.',
    formulas: ['ΔHᵢ = Hᵢ − Hprojet', 'V = A × (ΔH₁ + ΔH₂ + ΔH₃) / 3'],
    steps: [
      'Saisir un point X,Y,H par ligne, en mètres.',
      'Saisir trois indices par triangle, en numérotant les points à partir de 1.',
      'Entrer la cote de projet puis calculer la surface en plan, le déblai, le remblai et le volume net.'
    ],
    example: [
      ('Points', '(0,0,12) / (10,0,12) / (0,10,12)'),
      ('Triangle / cote de projet', '1,2,3 / 10 m'),
      ('Surface / déblai', '50 m² / 100 m³')
    ],
    notes: [
      'Le signe du volume classe chaque triangle. Un triangle qui traverse le plan de projet contribue par son volume net.'
    ],
  ),
  'inverse': Tutorial(
    title: 'Calcul inverse de coordonnées',
    summary:
        'Calculer la distance horizontale et le gisement entre deux points connus.',
    formulas: [
      'ΔN = NB − NA ; ΔE = EB − EA',
      'D = √(ΔN² + ΔE²)',
      'G = atan2(ΔE, ΔN), ramené dans [0°, 360°['
    ],
    steps: [
      'Saisir les coordonnées nord (X) et est (Y) des deux points.',
      'Vérifier la direction sur le plan et exporter le tableau si nécessaire.'
    ],
    example: [
      ('A → B', '(1 000 ; 2 000) → (1 080 ; 2 060)'),
      ('D / G', '100,000 m / 36°52′11,6″')
    ],
    notes: [
      'Le gisement se mesure dans le sens horaire à partir du nord. Deux points confondus ne définissent aucune direction.'
    ],
  ),
  'polar': Tutorial(
    title: 'Calcul direct de coordonnées',
    summary:
        'Déterminer un point à partir d’une station connue, d’un gisement et d’une distance horizontale.',
    formulas: ['NB = NA + D·cos G', 'EB = EA + D·sin G'],
    steps: [
      'Saisir la station, le gisement et la distance horizontale.',
      'Lire les coordonnées du point calculé ou vérifier la visée sur le plan.'
    ],
    example: [
      ('Station', 'N = 1 000 m ; E = 2 000 m'),
      ('Gisement / distance', '36°52′11,6″ / 50 m'),
      ('Point calculé', 'N ≈ 1 040 m ; E ≈ 2 030 m')
    ],
    notes: [
      'Choisir DMS, degrés décimaux ou radians pour la saisie des angles. Pour un angle relatif à une visée arrière, utiliser le calcul d’implantation.'
    ],
  ),
  'stakeout': Tutorial(
    title: 'Calcul d’implantation',
    summary:
        'Calculer la rotation horaire de la visée arrière vers la cible et la distance horizontale à implanter.',
    formulas: ['β = (Gcible − Garrière) mod 360°', 'D = √(ΔN² + ΔE²)'],
    steps: [
      'Saisir la station occupée et le point arrière connu.',
      'Saisir la cible, puis relever la rotation et la distance calculées.'
    ],
    example: [
      ('Station / point arrière', '(1 000 ; 2 000) / (1 100 ; 2 000)'),
      ('Cible', '(1 040 ; 2 030)'),
      ('β / D', '36°52′11,6″ / 50,000 m')
    ],
    notes: [
      'La distance est horizontale. Une distance inclinée exige une observation verticale supplémentaire.'
    ],
  ),
  'batch_stakeout': Tutorial(
    title: 'Implantation par lots',
    summary:
        'Calculer les rotations et les distances horizontales de plusieurs cibles depuis une même station.',
    formulas: ['βᵢ = (Gᵢ − Garrière) mod 360°', 'Dᵢ = √(ΔNᵢ² + ΔEᵢ²)'],
    steps: [
      'Saisir une fois la station et le point arrière.',
      'Ajouter le numéro, le nord et l’est de chaque cible.',
      'Sélectionner un résultat dans le tableau ou sur le plan, puis copier le CSV ou exporter.'
    ],
    example: [
      ('Station / point arrière', '(1 000 ; 2 000) / (1 100 ; 2 000)'),
      ('Cible', 'P1, 1040, 2030'),
      ('P1', '36°52′11,6″ / 50,000 m')
    ],
    notes: [
      'Une cible confondue avec la station est signalée. Le calcul des autres cibles continue.'
    ],
  ),
  'resection': Tutorial(
    title: 'Relèvement angulaire sur trois points',
    summary:
        'Déterminer une station inconnue par des angles horaires vers trois points d’appui connus.',
    formulas: [
      'Les cordes AB et BC et leurs angles observés déterminent deux cercles passant par B et la station P.'
    ],
    steps: [
      'Saisir les coordonnées de A, B et C dans l’ordre des observations.',
      'Depuis P, saisir les angles horaires A→B et B→C.'
    ],
    example: [
      ('A / B / C', '(100 ; 0) / (120 ; 120) / (0 ; 100)'),
      ('Angles / P', '45° / 45° → (0 ; 0)')
    ],
    notes: [
      'Sur le cercle dangereux, les deux cercles coïncident et la station ne peut être déterminée de façon unique.'
    ],
  ),
  'intersection': Tutorial(
    title: 'Intersection angulaire',
    summary:
        'Déterminer P à partir des points connus A et B et des angles mesurés à ces points.',
    formulas: [
      'γ = 180° − α − β',
      'Np = [Na·tan α + Nb·tan β + (Eb−Ea)·tan α·tan β] / (tan α + tan β)',
      'Ep = [Ea·tan α + Eb·tan β + (Na−Nb)·tan α·tan β] / (tan α + tan β)',
    ],
    steps: [
      'Saisir les coordonnées de A et B.',
      'Saisir ∠BAP en A et ∠ABP en B. Examiner les valeurs intermédiaires et la solution sur le plan.'
    ],
    example: [
      ('A / B', '(659,232 ; 355,537) / (406,593 ; 654,051)'),
      ('α / β', '69°11′03″ / 59°42′39″'),
      ('P', '(869,198 ; 735,228)')
    ],
    notes: [
      'Un angle d’intersection faible amplifie les erreurs angulaires. Le mode par distances utilise AP et BP.'
    ],
  ),
  'traverse': Tutorial(
    title: 'Compensation de cheminement',
    summary:
        'Compenser les angles et les coordonnées d’un cheminement fermé ou encadré par des points connus.',
    formulas: [
      'fβ = Σβobservés − Σβthéoriques',
      'fN = ΣΔN − (Nfin − Ndépart)',
      'fE = ΣΔE − (Efin − Edépart)',
      'f = √(fN² + fE²) ; 1/K = f / ΣD'
    ],
    steps: [
      'Choisir le type de cheminement et le sens des angles.',
      'Saisir les points d’appui, les gisements et les observations.',
      'Vérifier les fermetures angulaire et linéaire. Répartir les corrections par longueur ou par composante des coordonnées.'
    ],
    example: [
      ('Départ', 'N = 536,27 m ; E = 328,74 m ; G = 48°43′18″'),
      ('Fermeture angulaire', '−60,0″, tolérance ±89,4″'),
      ('Fermeture linéaire', '0,119 m, soit environ 1:4 081')
    ],
    notes: [
      'En boucle fermée, contrôler la convention d’angles intérieurs ou extérieurs avant de valider le résultat.'
    ],
  ),
  'leveling': Tutorial(
    title: 'Compensation de nivellement',
    summary:
        'Compenser des dénivelées observées entre des altitudes connues. Le mode à double face contrôle également chaque station.',
    formulas: [
      'fh = ΣΔH − (Hfin − Hdépart)',
      'vᵢ = −fh × wᵢ / Σw',
      'ΔH compensée = ΔH + vᵢ'
    ],
    steps: [
      'Saisir les altitudes connues et les dénivelées observées.',
      'Saisir les longueurs des tronçons ou les nombres de stations selon la pondération choisie.',
      'Contrôler la fermeture, les corrections et les altitudes compensées.'
    ],
    example: [
      ('Boucle fermée', 'ΣΔH = +8 mm'),
      ('Correction totale', 'Σv = −8 mm')
    ],
    notes: [
      'Saisir les poids dans une unité cohérente et sélectionner la tolérance du projet.'
    ],
  ),
  'precision': Tutorial(
    title: 'Évaluation de la précision',
    summary:
        'Calculer la moyenne et l’écart-type expérimental d’observations répétées ou de résidus.',
    formulas: ['x̄ = Σxᵢ / n', 's = √[Σ(xᵢ − x̄)² / (n − 1)]'],
    steps: [
      'Saisir les valeurs dans une même unité.',
      'Relever la moyenne, l’écart-type et l’écart maximal à la moyenne.'
    ],
    example: [
      ('Observations', '9 ; 10 ; 11'),
      ('Moyenne / écart-type', '10 / 1')
    ],
    notes: [
      'Le calcul de l’écart-type expérimental exige au moins deux observations.'
    ],
  ),
  'circular_curve': Tutorial(
    title: 'Éléments de courbe circulaire',
    summary:
        'Calculer les tangentes, l’arc, la distance extérieure et les chaînages principaux à partir de la déflexion et du rayon.',
    formulas: [
      'T = R·tan(α/2)',
      'L = R·α·π/180',
      'E = R·(sec(α/2) − 1)',
      'q = 2T − L'
    ],
    steps: [
      'Saisir le chaînage de l’intersection, la déflexion et le rayon.',
      'Relever les éléments et les chaînages du début, du milieu et de la fin de la courbe.'
    ],
    example: [('α / R', '40° / 300 m'), ('T / L', '109,19 m / 209,44 m')],
    notes: [
      'Utiliser la valeur absolue de la déflexion pour les longueurs. Respecter le côté de la courbe à l’implantation.'
    ],
  ),
  'clothoid': Tutorial(
    title: 'Raccordement clothoïde',
    summary:
        'Calculer la géométrie du raccordement entre une tangente et un arc circulaire.',
    formulas: [
      'A = √(R·l)',
      'p ≈ l²/(24R) − l⁴/(2688R³)',
      'm ≈ l/2 − l³/(240R²)',
      'T = (R + p)·tan(α/2) + m'
    ],
    steps: [
      'Saisir le rayon, la longueur de raccordement et la déflexion totale.',
      'Examiner le ripage, la longueur d’arc et les chaînages des raccordements.'
    ],
    example: [('R / l', '300 m / 60 m'), ('p / m', '≈ 0,50 m / 29,99 m')],
    notes: [
      'Vérifier la longueur de raccordement selon les critères de conception du projet.'
    ],
  ),
  'vertical_curve': Tutorial(
    title: 'Courbe de raccordement vertical',
    summary:
        'Calculer un profil parabolique entre deux pentes et consulter l’altitude projetée à un chaînage donné.',
    formulas: [
      'ω = i₂ − i₁',
      'L = R·|ω| ; T = L/2',
      'H = Hdébut + i₁·x + ω·x²/(2L)'
    ],
    steps: [
      'Saisir le chaînage et l’altitude de l’intersection, les deux pentes et le rayon.',
      'Relever les éléments de la courbe ou saisir le chaînage de l’altitude souhaitée.'
    ],
    example: [
      ('Pentes / rayon', '+2,0 % / −1,5 % ; R = 5 000 m'),
      ('L / T', '175 m / 87,5 m')
    ],
    notes: [
      'Une montée dans le sens des chaînages croissants est positive. Dans les formules, convertir les pourcentages en fractions.'
    ],
  ),
  'route_stake': Tutorial(
    title: 'Abscisses et ordonnées d’implantation',
    summary:
        'Calculer les déports tangentiel et normal à une distance donnée le long d’un arc circulaire ou d’une clothoïde.',
    formulas: ['Arc circulaire : θ = s/R ; x = R·sin θ ; y = R·(1 − cos θ)'],
    steps: [
      'Choisir le type de courbe et saisir sa géométrie.',
      'Entrer la longueur parcourue depuis le début de la courbe, puis relever les déports locaux.'
    ],
    example: [
      ('Arc circulaire', 'R = 100 m ; s = 50 m'),
      ('x / y', '47,943 m / 12,242 m')
    ],
    notes: ['L’origine et les axes sont définis au début de la courbe.'],
  ),
  'area': Tutorial(
    title: 'Aire d’un polygone',
    summary:
        'Calculer l’aire, le périmètre et le centroïde à partir des sommets ordonnés du contour.',
    formulas: ['S = ½·|Σ(NᵢEᵢ₊₁ − Nᵢ₊₁Eᵢ)|', 'P = ΣDᵢ'],
    steps: [
      'Saisir les sommets dans l’ordre du contour, dans un sens ou dans l’autre.',
      'Contrôler le dessin, puis exporter l’aire et les résultats par côté.'
    ],
    example: [
      ('Sommets', '(0 ; 0), (100 ; 0), (100 ; 50), (0 ; 50)'),
      ('Aire / périmètre', '5 000 m² / 300 m')
    ],
    notes: [
      'Le contour doit être simple. Un polygone qui se recoupe ne représente pas une parcelle unique.'
    ],
  ),
  'earthwork': Tutorial(
    title: 'Cubatures de terrassement',
    summary:
        'Estimer les déblais et les remblais sur un quadrillage ou calculer un volume entre profils en travers.',
    formulas: [
      'Moyenne des sections : V = Σ[Dᵢ·(Aᵢ + Aᵢ₊₁)/2]',
      'Quadrillage : Vnet = Vdéblai − Vremblai'
    ],
    steps: [
      'Pour les profils, entrer les aires des sections et les intervalles.',
      'Pour le quadrillage, saisir la maille et les différences de cote aux sommets selon la convention affichée.',
      'Examiner les totaux et les mailles recoupées par la ligne de terrassement nul.'
    ],
    example: [
      ('Sections', 'A₁ = 10 m² ; A₂ = 14 m² ; D = 20 m'),
      ('Volume', '240 m³')
    ],
    notes: [
      'Les mailles mixtes sont scindées à la ligne où la différence de cote est nulle.'
    ],
  ),
  'projection': Tutorial(
    title: 'Transformations de coordonnées',
    summary:
        'Utiliser la projection de Gauss–Krüger, une similitude plane, une conversion géodésique/cartésienne ou une transformation à sept paramètres.',
    formulas: [
      'Similitude plane : N₂ = dN + k(N₁cos θ − E₁sin θ)',
      'E₂ = dE + k(N₁sin θ + E₁cos θ)'
    ],
    steps: [
      'Choisir la méthode, l’ellipsoïde et les conventions.',
      'Pour un ajustement, saisir les points communs et examiner les résidus avant application.',
      'Vérifier le méridien central et la fausse abscisse en projection.'
    ],
    example: [
      ('Gauss–Krüger', 'B = 39,9°, L = 116,4°, CGCS2000, fuseau de 3°'),
      (
        'Résultat',
        'N ≈ 4 418 598,001 m ; E ≈ 448 688,856 m ; méridien central 117°'
      )
    ],
    notes: [
      'Documenter le fuseau, la fausse abscisse et la convention de rotation lors de tout échange de coordonnées.'
    ],
  ),
  'leveling4': Tutorial(
    title: 'Nivellement différentiel de quatrième ordre',
    summary:
        'Enregistrer les lectures sur les deux faces des mires, contrôler chaque station et compenser le parcours aux repères connus.',
    formulas: [
      'Stadia : D = 0,1·|fil supérieur − fil inférieur|, lectures en mm et distance en m.',
      'd = Darrière − Davant ; cumuler Σd.',
      'Contrôle de mire : K + noir − rouge.',
      'ΔH = [ΔH noir + ΔH rouge − (K arrière − K avant)] / 2.'
    ],
    steps: [
      'Saisir les faces noire et rouge en arrière, puis les faces noire et rouge en avant.',
      'En mode électronique, saisir les distances directes. Contrôler les constantes des mires et la cohérence des lectures.',
      'Saisir les altitudes connues aux extrémités, puis examiner la fermeture et les corrections.'
    ],
    example: [
      ('Fils arrière / avant', '1571/1197 / 1385/998 mm'),
      ('Faces arrière / avant', '1384/6071 / 1211/5998 mm'),
      ('d / ΔH', '−1,3 m / +173 mm')
    ],
    notes: [
      'Portée réglée à 80 m ou 100 m. |d| ≤ 3 m, |Σd| ≤ 10 m avec alerte à 7 m, contrôle de mire à 3 mm et écart des dénivelées corrigées à 5 mm.',
      'Par distance, les options plaine et montagne utilisent ±20√L et ±25√L mm, L étant la longueur en km.'
    ],
  ),
  'quadrant': Tutorial(
    title: 'Gisement et angle de quadrant',
    summary:
        'Passer d’un gisement horaire compté depuis le nord à un angle de quadrant, ou inversement.',
    formulas: [
      'NE : R = G',
      'SE : R = 180° − G',
      'SO : R = G − 180°',
      'NO : R = 360° − G'
    ],
    steps: ['Saisir le gisement, ou choisir le quadrant puis saisir l’angle.'],
    example: [
      ('Gisement', '123°45′30″'),
      ('Angle de quadrant', 'S 56°14′30″ E')
    ],
    notes: [
      'Sur une direction cardinale, le gisement distingue précisément la limite de quadrant.'
    ],
  ),
  'convert': Tutorial(
    title: 'Conversions d’unités',
    summary: 'Convertir les angles, la pente et les distances.',
    formulas: ['1° = 60′ = 3600″ = π/180 rad', 'Pente (%) = 100·tan θ'],
    steps: [
      'Choisir la grandeur et saisir la valeur dans son unité de départ. Lire les valeurs converties.'
    ],
    example: [
      ('Angle', '36°52′11,6″ ≈ 36,869889°'),
      ('Pente', '2 % ≈ 1,1458°')
    ],
    notes: [
      'Le DMS compact sépare les degrés des minutes et secondes : saisir 36.5211 pour 36°52′11″.'
    ],
  ),
  'formula': Tutorial(
    title: 'Calculatrice de formules hors ligne',
    summary:
        'Évaluer une expression à variables nommées ou charger une formule de la bibliothèque intégrée.',
    formulas: [
      'Opérateurs : + − × ÷ ^',
      'Fonctions : sin, cos, tan, atan2, sqrt, abs et ln.'
    ],
    steps: [
      'Saisir l’expression et, au besoin, les variables.',
      'Calculer le résultat ou sélectionner une formule de la bibliothèque.'
    ],
    example: [
      ('Expression à saisir', '100*sin(36.86989765)'),
      ('Résultat', '≈ 60')
    ],
    notes: [
      'Les fonctions trigonométriques directes prennent des degrés décimaux. Les fonctions inverses renvoient des radians, convertibles avec deg(…).'
    ],
  ),
  'control_points': Tutorial(
    title: 'Bibliothèque de points de contrôle',
    summary:
        'Gérer les points de contrôle du projet (identifiant, Nord X, Est Y, altitude H, groupe et notes) avec import/export CSV/DXF et sélection directe dans les outils.',
    formulas: [
      'CSV standard : Nom, X (Nord), Y (Est), H (Altitude), Groupe, Note',
      'CSV CASS : Nom, Code, Y (Est), X (Nord), H (Altitude)'
    ],
    steps: [
      'Ajouter des points manuellement ou importer en lot depuis un fichier CSV ou DXF.',
      'Filtrer par groupe ou mot-clé avec détection en temps réel des doublons.',
      'Projeter le réseau sur LivePlot (Nord X vers le haut, Est Y vers la droite).',
      'Sélectionner un point en un clic depuis les outils de calcul topographique.'
    ],
    example: [
      ('Point de contrôle', 'K1 : X=3054120,450, Y=523410,120, H=845,320'),
      ('Export', 'CSV standard et format d’échange CASS')
    ],
    notes: [
      'La convention topographique est respectée : X correspond au Nord et Y à l’Est.',
      'Les fichiers CASS placent Y (Est) avant X (Nord) lors de l’importation.'
    ],
  ),
};
