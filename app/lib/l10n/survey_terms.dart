import 'form_terms.dart';

/// Compact labels shared by the tools, charts, and printable survey forms.
const surveyTerms = <String, (String, String, String, String)>{
  ...surveyFormTerms,
  '后尺 {back}，前尺 {front}。|K+黑−红| ≤ 3 mm，|d| ≤ {limit} m，|Σd| ≤ 10 m（±7 m 预警），视线高 > 0.2 m。': (
    'BS {back}, FS {front}. |K+B−R| ≤ 3 mm, |d| ≤ {limit} m, |Σd| ≤ 10 m (warning at ±7 m), sight height > 0.2 m.',
    'Arrière {back}, avant {front}. |K+N−R| ≤ 3 mm, |d| ≤ {limit} m, |Σd| ≤ 10 m (alerte à ±7 m), hauteur de visée > 0,2 m.',
    'Ré {back}, vante {front}. |K+preta−vermelha| ≤ 3 mm, |d| ≤ {limit} m, |Σd| ≤ 10 m (aviso a ±7 m), altura de visada > 0,2 m.',
    'Atrás {back}, adelante {front}. |K+negra−roja| ≤ 3 mm, |d| ≤ {limit} m, |Σd| ≤ 10 m (aviso a ±7 m), altura de visual > 0,2 m.',
  ),
  '单站视距差限差': ('Station sight-distance difference limit', 'Écart de portée maximal par station', 'Limite de diferença de visadas por estação', 'Límite de diferencia de visuales por estación'),
  '更多操作': ('More actions', 'Plus d’actions', 'Mais ações', 'Más acciones'),
  '页面工具栏': (
    'Page toolbar',
    'Barre d’outils',
    'Barra de ferramentas',
    'Barra de herramientas'
  ),
  '前方交会 · 30°–150°': (
    'Forward intersection · 30°–150°',
    'Intersection · 30°–150°',
    'Interseção à frente · 30°–150°',
    'Intersección directa · 30°–150°'
  ),
  '双面尺 · 逐站检核': (
    'Dual-face · station checks',
    'Deux faces · contrôles de station',
    'Duas faces · verificações',
    'Doble cara · control por estación'
  ),
  '打开离线教程': (
    'Open offline guide',
    'Ouvrir le guide hors ligne',
    'Abrir o guia offline',
    'Abrir la guía sin conexión'
  ),
  '长按公式可复制': (
    'Long-press a formula to copy it',
    'Appuyer longuement sur la formule pour la copier',
    'Mantenha a fórmula premida para a copiar',
    'Mantén pulsada la fórmula para copiarla'
  ),
  '公式已复制': (
    'Formula copied',
    'Formule copiée',
    'Fórmula copiada',
    'Fórmula copiada'
  ),
  '四等水准教程': (
    'Fourth-order levelling guide',
    'Guide du nivellement de quatrième ordre',
    'Guia de nivelamento de quarta ordem',
    'Guía de nivelación de cuarto orden'
  ),
  '教程 · {tool}': (
    'Guide · {tool}',
    'Guide · {tool}',
    'Guia · {tool}',
    'Guía · {tool}'
  ),
  '公式': ('Formulas', 'Formules', 'Fórmulas', 'Fórmulas'),
  '怎么用': ('Procedure', 'Procédure', 'Procedimento', 'Procedimiento'),
  '算例': (
    'Worked example',
    'Exemple de calcul',
    'Exemplo de cálculo',
    'Ejemplo de cálculo'
  ),
  '注意': ('Notes', 'Remarques', 'Notas', 'Notas'),
  // English, French, Portuguese, Spanish.
  '观测手簿': (
    'Field book',
    'Carnet de terrain',
    'Caderneta de campo',
    'Libreta de campo'
  ),
  '三（四）等水准测量观测手簿': (
    'Order 3/4 levelling field book',
    'Carnet de nivellement d’ordre 3/4',
    'Caderneta de nivelamento de 3.ª/4.ª ordem',
    'Libreta de nivelación de 3.er/4.º orden'
  ),
  '成果计算表': ('Results', 'Résultats', 'Resultados', 'Resultados'),
  '曲线计算表': (
    'Curve calculations',
    'Calculs de courbe',
    'Cálculo de curvas',
    'Cálculo de curvas'
  ),
  '交会坐标计算表': (
    'Intersection coordinates',
    'Coordonnées d’intersection',
    'Coordenadas de interseção',
    'Coordenadas de intersección'
  ),
  '备注': ('Notes', 'Remarques', 'Observações', 'Observaciones'),
  '点号': ('Point ID', 'N° du point', 'N.º do ponto', 'N.º de punto'),
  '测站\n编号': (
    'Station\nID',
    'N° de\nstation',
    'N.º da\nestação',
    'N.º de\nestación'
  ),
  '方向\n及\n尺号': (
    'Sight /\nstaff ID',
    'Visée /\nmire',
    'Visada /\nmira',
    'Visual /\nmira'
  ),
  '后\n尺': ('Back\nstaff', 'Mire\narrière', 'Mira\nde ré', 'Mira\natrás'),
  '前\n尺': ('Fore\nstaff', 'Mire\navant', 'Mira\nde vante', 'Mira\nadelante'),
  '后视距': (
    'BS distance',
    'Portée arrière',
    'Distância de ré',
    'Distancia atrás'
  ),
  '前视距': (
    'FS distance',
    'Portée avant',
    'Distância de vante',
    'Distancia adelante'
  ),
  '上丝': ('Upper', 'Supérieur', 'Superior', 'Superior'),
  '下丝': ('Lower', 'Inférieur', 'Inferior', 'Inferior'),
  '黑面': ('Black face', 'Face noire', 'Face preta', 'Cara negra'),
  '红面': ('Red face', 'Face rouge', 'Face vermelha', 'Cara roja'),
  '高差\n中数\n(m)': (
    'Mean ΔH\n(m)',
    'ΔH moyen\n(m)',
    'ΔH médio\n(m)',
    'ΔH medio\n(m)'
  ),
  '高差中数': ('Mean ΔH', 'ΔH moyen', 'ΔH médio', 'ΔH medio'),
  'K+黑-红\n(mm)': (
    'K+black−red\n(mm)',
    'K+noir−rouge\n(mm)',
    'K+preto−vermelho\n(mm)',
    'K+negro−rojo\n(mm)'
  ),
  '视距d(m)': (
    'Sight diff. d (m)',
    'Écart d (m)',
    'Dif. de visadas d (m)',
    'Dif. de visuales d (m)'
  ),
  '项目': ('Item', 'Rubrique', 'Item', 'Concepto'),
  '值': ('Value', 'Valeur', 'Valor', 'Valor'),
  '单位': ('Unit', 'Unité', 'Unidade', 'Unidad'),
  '中央子午线': (
    'Central meridian',
    'Méridien central',
    'Meridiano central',
    'Meridiano central'
  ),
  '带号': ('Zone', 'Fuseau', 'Fuso', 'Huso'),
  '纬度': ('Latitude', 'Latitude', 'Latitude', 'Latitud'),
  '经度': ('Longitude', 'Longitude', 'Longitude', 'Longitud'),
  '闭合差': (
    'Misclosure',
    'Écart de fermeture',
    'Erro de fecho',
    'Error de cierre'
  ),
  '高程': ('Elevation', 'Altitude', 'Cota', 'Cota'),
  '等级': ('Order', 'Ordre', 'Ordem', 'Orden'),
  '观测方法': (
    'Observation method',
    'Méthode de mesure',
    'Método de observação',
    'Método de observación'
  ),
  '校核': ('Verification', 'Contrôle', 'Verificação', 'Verificación'),
  '检核': ('Check', 'Contrôle', 'Verificação', 'Comprobación'),
  '注意事项': ('Notes', 'Précautions', 'Precauções', 'Precauciones'),
  '方位角': ('Azimuth', 'Azimut', 'Azimute', 'Acimut'),
  '路线总长': (
    'Route length',
    'Longueur du parcours',
    'Comprimento do percurso',
    'Longitud del itinerario'
  ),
  '限差': ('Tolerance', 'Tolérance', 'Tolerância', 'Tolerancia'),
  '弧长': (
    'Arc length',
    'Longueur d’arc',
    'Comprimento do arco',
    'Longitud de arco'
  ),
  '半径': ('Radius', 'Rayon', 'Raio', 'Radio'),
  '代入当前读数': (
    'Substitute current readings',
    'Substituer les mesures actuelles',
    'Substituir as leituras atuais',
    'Sustituir las lecturas actuales'
  ),
  '代入当前数据': (
    'Substitute current values',
    'Substituer les valeurs actuelles',
    'Substituir os valores atuais',
    'Sustituir los valores actuales'
  ),
  '完成录入后显示代入步骤': (
    'Enter valid inputs to see the calculation.',
    'Saisissez des valeurs valides pour afficher le calcul.',
    'Introduza valores válidos para ver o cálculo.',
    'Introduzca valores válidos para ver el cálculo.'
  ),
};

String? localizedSurveyTerm(String code, String source) {
  final term = surveyTerms[source];
  if (term == null) return null;
  return switch (code) {
    'fr' => term.$2,
    'pt' => term.$3,
    'es' => term.$4,
    _ => term.$1,
  };
}
