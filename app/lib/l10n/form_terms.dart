const surveyFormTerms = <String, (String, String, String, String)>{
  '日期': ('Date', 'Date', 'Data', 'Fecha'),
  '制表': ('Prepared', 'Établi', 'Elaborado', 'Elaborado'),
  '观测': ('Observed', 'Observé', 'Observação', 'Observación'),
  '记录': ('Recorded', 'Noté', 'Registo', 'Registro'),
  '计算': ('Computed', 'Calculé', 'Cálculo', 'Cálculo'),
  '复核': ('Checked', 'Vérifié', 'Revisto', 'Revisado'),
  '指导教师': ('Instructor', 'Enseignant', 'Orientador', 'Docente'),
  '班级/工程': (
    'Class/Project',
    'Classe/Projet',
    'Turma/Projeto',
    'Clase/Proyecto'
  ),
  '小组': ('Group', 'Groupe', 'Grupo', 'Grupo'),
  '天气': ('Weather', 'Météo', 'Tempo', 'Tiempo'),
  '当前': ('Current', 'Actuel', 'Atual', 'Actual'),
  '距离交会检核': (
    'Distance intersection check',
    'Contrôle de l’intersection par distances',
    'Verificação da interseção por distâncias',
    'Comprobación de la intersección por distancias',
  ),
  '两组圆交点解已列出，请结合现场左右侧判别选用。': (
    'Two circle intersections are listed. Choose the solution on the observed side of the baseline.',
    'Deux intersections sont indiquées. Choisissez celle du côté observé de la base.',
    'São indicadas duas interseções. Escolha a solução do lado observado da base.',
    'Se muestran dos intersecciones. Elija la solución del lado observado de la base.',
  ),
  '闭合差判定': (
    'Misclosure check',
    'Contrôle de fermeture',
    'Verificação do fecho',
    'Comprobación del cierre'
  ),
  '路线类型': (
    'Route type',
    'Type de parcours',
    'Tipo de percurso',
    'Tipo de itinerario'
  ),
  '分配方式': ('Weighting', 'Pondération', 'Ponderação', 'Ponderación'),
  '测站数': (
    'Station count',
    'Nombre de stations',
    'Número de estações',
    'Número de estaciones'
  ),
  '{title}成果计算表': (
    '{title} results',
    'Résultats : {title}',
    'Resultados: {title}',
    'Resultados: {title}'
  ),
  '制表日期：{date}': (
    'Prepared on {date}',
    'Établi le {date}',
    'Elaborado em {date}',
    'Elaborado el {date}'
  ),
  '说明：本成果由工程测量工具箱离线解算。': (
    'Calculated offline in Survey Pro.',
    'Calculé hors ligne dans Survey Pro.',
    'Calculado offline no Survey Pro.',
    'Calculado sin conexión en Survey Pro.',
  ),
  '计算说明与检核附注：': (
    'Calculation and check notes:',
    'Notes de calcul et de contrôle :',
    'Notas de cálculo e verificação:',
    'Notas de cálculo y comprobación:'
  ),
  '平面示意略图：': (
    'Plan sketch:',
    'Croquis en plan :',
    'Esboço em planta:',
    'Croquis en planta:'
  ),
  '制表：________    计算：________    复核：________    日期：{date}': (
    'Prepared by: ________    Calculated by: ________    Reviewed by: ________    Date: {date}',
    'Établi par : ________    Calculé par : ________    Vérifié par : ________    Date : {date}',
    'Elaborado por: ________    Calculado por: ________    Revisto por: ________    Data: {date}',
    'Elaboró: ________    Calculó: ________    Revisó: ________    Fecha: {date}',
  ),
  '观测：________    记录：________    计算：________    校核：________    日期：{date}': (
    'Observed: ________    Recorded: ________    Calculated: ________    Checked: ________    Date: {date}',
    'Observé : ________    Noté : ________    Calculé : ________    Contrôlé : ________    Date : {date}',
    'Observação: ________    Registo: ________    Cálculo: ________    Verificação: ________    Data: {date}',
    'Observó: ________    Registró: ________    Calculó: ________    Comprobó: ________    Fecha: {date}',
  ),
  '起终点选用固定标志，转点使用尺垫，核对两尺常数 K。': (
    'Use fixed benchmarks at the endpoints and turning plates at turning points. Verify both staff constants K.',
    'Utiliser des repères fixes aux extrémités et des crapauds aux points de changement. Vérifier les deux constantes K.',
    'Use referências fixas nas extremidades e sapatas nos pontos de mudança. Verifique as duas constantes K.',
    'Use referencias fijas en los extremos y placas de apoyo en los puntos de cambio. Verifique las dos constantes K.',
  ),
  '测站限差：|d| ≤ {distance} m、|Σd| ≤ {cumulative} m、|K+黑−红| ≤ {constant} mm。': (
    'Station tolerances: |d| ≤ {distance} m, |Σd| ≤ {cumulative} m, |K+black−red| ≤ {constant} mm.',
    'Tolérances à la station : |d| ≤ {distance} m, |Σd| ≤ {cumulative} m, |K+noir−rouge| ≤ {constant} mm.',
    'Tolerâncias da estação: |d| ≤ {distance} m, |Σd| ≤ {cumulative} m, |K+preto−vermelho| ≤ {constant} mm.',
    'Tolerancias de estación: |d| ≤ {distance} m, |Σd| ≤ {cumulative} m, |K+negro−rojo| ≤ {constant} mm.',
  ),
  '视线长度 ≤ {sight} m。经尺常数改正的红黑面高差之差 ≤ {faces} mm。': (
    'Sight distance ≤ {sight} m. Difference between face height differences after staff correction ≤ {faces} mm.',
    'Portée ≤ {sight} m. Écart entre les dénivelées des deux faces après correction de mire ≤ {faces} mm.',
    'Distância de visada ≤ {sight} m. Diferença entre desníveis das faces após correção da mira ≤ {faces} mm.',
    'Distancia de visual ≤ {sight} m. Diferencia entre desniveles de las caras tras corregir las miras ≤ {faces} mm.',
  ),
  '计算顺序（对照手簿编号）：(1)(2) 后尺上/下丝→(9) 后视距；(3)(4) 黑面读数→(15) 黑差；'
      '(5)(6) 前尺上/下丝→(10) 前视距；(7)(8) 红面读数→(16) 红差；'
      '(11) d = 后视距 − 前视距 → (12) Σd；'
      '(13)(14) K + 黑 − 红 → (17) 检核差 → (18) 高差中数(m)。': (
    'Field-book sequence: (1)(2) BS stadia → (9) BS distance. (3)(4) black faces → (15) black ΔH. '
        '(5)(6) FS stadia → (10) FS distance. (7)(8) red faces → (16) red ΔH. '
        '(11) d = BS distance − FS distance → (12) Σd. (13)(14) K + black − red → (17) check → (18) mean ΔH (m).',
    'Carnet : (1)(2) fils arrière → (9) portée arrière. (3)(4) faces noires → (15) ΔH noir. '
        '(5)(6) fils avant → (10) portée avant. (7)(8) faces rouges → (16) ΔH rouge. '
        '(11) d = portée arrière − portée avant → (12) Σd. (13)(14) K + noir − rouge → (17) contrôle → (18) ΔH moyen (m).',
    'Caderneta: (1)(2) fios de ré → (9) distância de ré. (3)(4) faces pretas → (15) ΔH preto. '
        '(5)(6) fios de vante → (10) distância de vante. (7)(8) faces vermelhas → (16) ΔH vermelho. '
        '(11) d = distância de ré − distância de vante → (12) Σd. (13)(14) K + preto − vermelho → (17) verificação → (18) ΔH médio (m).',
    'Libreta: (1)(2) hilos atrás → (9) distancia atrás. (3)(4) caras negras → (15) ΔH negro. '
        '(5)(6) hilos adelante → (10) distancia adelante. (7)(8) caras rojas → (16) ΔH rojo. '
        '(11) d = distancia atrás − distancia adelante → (12) Σd. (13)(14) K + negro − rojo → (17) comprobación → (18) ΔH medio (m).',
  ),
  '高差中数(m) = [(黑后 − 黑前) + (红后 − 红前 − (K后 − K前))] ÷ 2 ÷ 1000。': (
    'Mean ΔH (m) = [black ΔH + red ΔH − (K backsight − K foresight)] ÷ 2000.',
    'ΔH moyen (m) = [ΔH noir + ΔH rouge − (K arrière − K avant)] ÷ 2000.',
    'ΔH médio (m) = [ΔH preto + ΔH vermelho − (K ré − K vante)] ÷ 2000.',
    'ΔH medio (m) = [ΔH negro + ΔH rojo − (K atrás − K adelante)] ÷ 2000.',
  ),
  '观测手簿（读数 mm，后尺 K={back}，前尺 K={front}）': (
    'Field book (readings in mm, BS K={back}, FS K={front})',
    'Carnet (lectures en mm, K arrière={back}, K avant={front})',
    'Caderneta (leituras em mm, K ré={back}, K vante={front})',
    'Libreta (lecturas en mm, K atrás={back}, K adelante={front})',
  ),
  '路线限差：±{coefficient}√L mm（L 为路线长，km）。': (
    'Route tolerance: ±{coefficient}√L mm, with L in km.',
    'Tolérance du parcours : ±{coefficient}√L mm, L en km.',
    'Tolerância do percurso: ±{coefficient}√L mm, com L em km.',
    'Tolerancia del itinerario: ±{coefficient}√L mm, con L en km.',
  ),
  '路线限差：±{coefficient}√n mm（n 为测站数）。': (
    'Route tolerance: ±{coefficient}√n mm, where n is the station count.',
    'Tolérance du parcours : ±{coefficient}√n mm, n étant le nombre de stations.',
    'Tolerância do percurso: ±{coefficient}√n mm, sendo n o número de estações.',
    'Tolerancia del itinerario: ±{coefficient}√n mm, con n igual al número de estaciones.',
  ),
  '闭合差按各站距离成比例分配，Σ改正数 = −fh。': (
    'Distribute misclosure in proportion to station distances. Σ corrections = −fh.',
    'Répartir la fermeture au prorata des distances. Σ corrections = −fh.',
    'Distribua o fecho na proporção das distâncias. Σ correções = −fh.',
    'Distribuya el cierre en proporción a las distancias. Σ correcciones = −fh.',
  ),
  '闭合差按站数平均分配，Σ改正数 = −fh。': (
    'Distribute misclosure equally between stations. Σ corrections = −fh.',
    'Répartir la fermeture à parts égales entre les stations. Σ corrections = −fh.',
    'Distribua o fecho igualmente pelas estações. Σ correções = −fh.',
    'Distribuya el cierre por igual entre estaciones. Σ correcciones = −fh.',
  ),
};
