(function () {
  'use strict';

  var STORAGE_KEY = 'adaptation-insights-language';
  var LANGS = ['en', 'fr', 'es'];
  var LANG_INDEX = { fr: 0, es: 1 };

  // French and Spanish are paired so the English source remains the single key.
  // Research statements and downloaded source data stay in their original wording.
  var TEXT = {
    'Adaptation Insights — Home': ['Adaptation Insights — Accueil', 'Adaptation Insights — Inicio'],
    'Adaptation Insights — Explore the data': ['Adaptation Insights — Explorer les données', 'Adaptation Insights — Explorar los datos'],
    'Adaptation Insights — Methods': ['Adaptation Insights — Méthodes', 'Adaptation Insights — Métodos'],
    'Adaptation Insights — About': ['Adaptation Insights — À propos', 'Adaptation Insights — Acerca de'],
    'Skip to content': ['Aller au contenu', 'Ir al contenido'],
    'Skip to the map': ['Aller à la carte', 'Ir al mapa'],
    'Home': ['Accueil', 'Inicio'],
    'Explore the data': ['Explorer les données', 'Explorar los datos'],
    'Explore': ['Explorer', 'Explorar'],
    'Methods': ['Méthodes', 'Métodos'],
    'About': ['À propos', 'Acerca de'],
    'Main': ['Navigation principale', 'Navegación principal'],
    'Footer': ['Pied de page', 'Pie de página'],
    'Partners': ['Partenaires', 'Socios'],
    'Where adaptation happens, for whom, and what': ['Où l’adaptation a lieu, pour qui et quels sont les', 'Dónde ocurre la adaptación, para quién y qué'],
    'changed.': ['changements.', 'cambió.'],
    'Results from project evaluations and completion reports, read page by page and placed on the map.': ['Des résultats tirés d’évaluations et de rapports d’achèvement de projets, lus page par page et situés sur la carte.', 'Resultados de evaluaciones e informes de finalización de proyectos, leídos página por página y ubicados en el mapa.'],
    'Open the globe': ['Ouvrir le globe', 'Abrir el globo'],
    'How the data is made': ['Comment les données sont produites', 'Cómo se elaboran los datos'],
    'Projects in the pilot': ['Projets du pilote', 'Proyectos del piloto'],
    'Pick one to open it on the globe.': ['Choisissez un projet pour l’ouvrir sur le globe.', 'Elija un proyecto para abrirlo en el globo.'],
    'projects': ['projets', 'proyectos'],
    'run': ['mènent', 'llevan a cabo'],
    'interventions': ['interventions', 'intervenciones'],
    'reporting': ['qui rapportent', 'que informan de'],
    'results': ['résultats', 'resultados'],
    'across': ['selon', 'en'],
    'metrics': ['indicateurs', 'indicadores'],
    'Updated 18 November 2026': ['Mis à jour le 18 novembre 2026', 'Actualizado el 18 de noviembre de 2026'],
    'Download the dataset (JSON)': ['Télécharger le jeu de données (JSON)', 'Descargar el conjunto de datos (JSON)'],
    'Adaptation Insights · Pilot dataset, 18 November 2026': ['Adaptation Insights · Jeu de données pilote, 18 novembre 2026', 'Adaptation Insights · Conjunto de datos piloto, 18 de noviembre de 2026'],
    '8 projects run 49 interventions, which report 227 results across 35 metrics. Updated 18 November 2026.': ['8 projets mènent 49 interventions, qui rapportent 227 résultats selon 35 indicateurs. Mis à jour le 18 novembre 2026.', '8 proyectos llevan a cabo 49 intervenciones, que informan de 227 resultados en 35 indicadores. Actualizado el 18 de noviembre de 2026.'],

    'From PDF to data point': ['Du PDF au point de données', 'Del PDF al dato'],
    "Each project document is read in full. Every figure is recorded with the document's wording and the page it came from.": ['Chaque document de projet est lu intégralement. Chaque chiffre est enregistré avec les termes du document et la page dont il est issu.', 'Cada documento del proyecto se lee íntegramente. Cada cifra se registra con la redacción del documento y la página de la que procede.'],
    '1 · The page': ['1 · La page', '1 · La página'],
    'Final evaluation': ['Évaluation finale', 'Evaluación final'],
    'Read, coded and checked against the page': ['Lu, codé et vérifié sur la page', 'Leído, codificado y cotejado con la página'],
    '2 · The record': ['2 · La fiche', '2 · El registro'],
    'khettaras rehabilitated (8,800 linear metres)': ['khettaras réhabilitées (8 800 mètres linéaires)', 'khettaras rehabilitadas (8.800 metros lineales)'],
    'Metric': ['Indicateur', 'Indicador'],
    'Infrastructure built/rehabilitated': ['Infrastructures construites/réhabilitées', 'Infraestructura construida/rehabilitada'],
    'Level': ['Niveau', 'Nivel'],
    'Output · positive · 2022': ['Produit · positif · 2022', 'Producto · positivo · 2022'],
    'Evidence': ['Données probantes', 'Evidencia'],
    'Routine monitoring data': ['Données de suivi courant', 'Datos de seguimiento rutinario'],
    'Source': ['Source', 'Fuente'],
    'Final evaluation, PDF p. 55': ['Évaluation finale, PDF p. 55', 'Evaluación final, PDF p. 55'],
    'Check': ['Vérification', 'Comprobación'],
    'Quote found on the page': ['Citation retrouvée sur la page', 'Cita localizada en la página'],
    'Six steps': ['Six étapes', 'Seis pasos'],
    'Collect': ['Collecter', 'Recopilar'],
    'Screen': ['Sélectionner', 'Seleccionar'],
    'Extract': ['Extraire', 'Extraer'],
    'Code': ['Coder', 'Codificar'],
    'Review': ['Réviser', 'Revisar'],
    "Completion reports and evaluations are gathered from the funders' public repositories into a shared Zotero library.": ['Les rapports d’achèvement et les évaluations sont rassemblés depuis les répertoires publics des bailleurs dans une bibliothèque Zotero partagée.', 'Los informes de finalización y las evaluaciones se recopilan de los repositorios públicos de los financiadores en una biblioteca compartida de Zotero.'],
    'A document is kept when it reports what a project did, the project started in 2015 or later in Africa, agriculture or food is its main subject, and it responds to a named climate risk. 225 of 1,647 documents met all criteria.': ['Un document est retenu s’il décrit ce qu’un projet a réalisé, si le projet a débuté en 2015 ou après en Afrique, si l’agriculture ou l’alimentation en est le sujet principal et s’il répond à un risque climatique identifié. 225 documents sur 1 647 remplissaient tous les critères.', 'Un documento se conserva si informa de lo que hizo un proyecto, si el proyecto comenzó en 2015 o después en África, si la agricultura o la alimentación es su tema principal y si responde a un riesgo climático identificado. 225 de 1.647 documentos cumplieron todos los criterios.'],
    'A fixed template records the project (dates, places, budget, funders, implementers, rationale, groups targeted) and every result reported with a number.': ['Un modèle fixe consigne le projet (dates, lieux, budget, bailleurs, responsables de la mise en œuvre, justification, groupes ciblés) ainsi que chaque résultat chiffré.', 'Una plantilla fija registra el proyecto (fechas, lugares, presupuesto, financiadores, ejecutores, justificación y grupos destinatarios) y cada resultado comunicado con una cifra.'],
    'Each quote is searched on the page cited: found exactly, read across a table, or computed by the reader. A value missing from its quote is set aside.': ['Chaque citation est recherchée sur la page indiquée : retrouvée à l’identique, lue dans un tableau ou calculée par la personne qui lit. Une valeur absente de sa citation est écartée.', 'Cada cita se busca en la página indicada: localizada de forma exacta, leída en una tabla o calculada por quien revisa el documento. Si el valor no aparece en su cita, se aparta.'],
    'Actors, places, metrics and units are matched to shared registers and lists. Wording with no fitting code is logged as a gap.': ['Les acteurs, lieux, indicateurs et unités sont rapprochés de registres et de listes partagés. Toute formulation sans code approprié est consignée comme une lacune.', 'Los actores, lugares, indicadores y unidades se vinculan con registros y listas compartidos. Las expresiones sin un código adecuado se registran como una laguna.'],
    'A reviewer checks each record before release. The review status travels with the downloaded data.': ['Une personne révise chaque fiche avant publication. Le statut de révision accompagne les données téléchargées.', 'Una persona revisa cada registro antes de su publicación. El estado de revisión acompaña a los datos descargados.'],
    'Read with care': ['À lire avec précaution', 'Leer con cautela'],
    'Figures are as reported by the projects, not independently verified.': ['Les chiffres sont ceux rapportés par les projets et n’ont pas été vérifiés de façon indépendante.', 'Las cifras son las comunicadas por los proyectos y no se han verificado de forma independiente.'],
    'Some places are not geocoded yet and are shown at an approximate position.': ['Certains lieux ne sont pas encore géocodés et sont affichés à une position approximative.', 'Algunos lugares aún no están geocodificados y se muestran en una posición aproximada.'],
    'The pilot records have not yet had a human QA review.': ['Les fiches du pilote n’ont pas encore fait l’objet d’un contrôle qualité humain.', 'Los registros del piloto aún no han pasado un control de calidad humano.'],
    'Mid-term documents give values part-way through a project, not final ones.': ['Les documents à mi-parcours donnent des valeurs relevées pendant le projet, et non des valeurs finales.', 'Los documentos de mitad de período ofrecen valores intermedios del proyecto, no valores finales.'],
    'Each project counts its beneficiaries in its own way. Figures from different projects are not always comparable.': ['Chaque projet compte ses bénéficiaires à sa manière. Les chiffres de projets différents ne sont pas toujours comparables.', 'Cada proyecto cuenta a sus beneficiarios a su manera. Las cifras de proyectos distintos no siempre son comparables.'],
    'Eight projects are a pilot, not a sample. Totals across them do not describe adaptation in Africa.': ['Ces huit projets constituent un pilote, pas un échantillon. Leurs totaux ne décrivent pas l’adaptation en Afrique.', 'Los ocho proyectos constituyen un piloto, no una muestra. Sus totales no describen la adaptación en África.'],

    'Why this': ['Pourquoi ce site', 'Por qué'],
    'exists': ['existe', 'existe'],
    'Projects learn a lot about what works in adaptation, but it stays in reports few people read. Adaptation Insights puts that evidence in one place you can search and compare.': ['Les projets apprennent beaucoup sur ce qui fonctionne en matière d’adaptation, mais ces enseignements restent dans des rapports que peu de personnes lisent. Adaptation Insights rassemble ces données probantes dans un espace où vous pouvez les rechercher et les comparer.', 'Los proyectos aprenden mucho sobre lo que funciona en adaptación, pero ese conocimiento queda en informes que pocas personas leen. Adaptation Insights reúne esa evidencia en un solo lugar donde se puede buscar y comparar.'],
    'What the data covers': ['Ce que couvrent les données', 'Qué abarcan los datos'],
    'Climate adaptation projects in African agriculture and food systems, as reported in their completion reports and evaluations. For each project the data gives where it worked, who funded and implemented it, whom it targeted, why it was needed, and the results it reported, each with the page it came from.': ['Des projets d’adaptation climatique dans l’agriculture et les systèmes alimentaires africains, tels que décrits dans leurs rapports d’achèvement et leurs évaluations. Pour chaque projet, les données indiquent où il est intervenu, qui l’a financé et mis en œuvre, quels groupes il ciblait, pourquoi il était nécessaire et quels résultats il a rapportés, avec la page source de chaque élément.', 'Proyectos de adaptación climática en la agricultura y los sistemas alimentarios africanos, según sus informes de finalización y evaluaciones. Para cada proyecto, los datos indican dónde trabajó, quién lo financió y ejecutó, a quién se dirigió, por qué era necesario y qué resultados comunicó, cada uno con su página de origen.'],
    "The pilot covers eight projects in eight countries, read from nine documents. The full dataset will cover the documents found in scope when the funders' repositories were screened in November 2026: 225 of 1,647.": ['Le pilote couvre huit projets dans huit pays, à partir de neuf documents. Le jeu de données complet couvrira les documents jugés pertinents lors du dépouillement des répertoires des bailleurs en novembre 2026 : 225 sur 1 647.', 'El piloto abarca ocho proyectos en ocho países, leídos en nueve documentos. El conjunto de datos completo abarcará los documentos considerados pertinentes al examinar los repositorios de los financiadores en noviembre de 2026: 225 de 1.647.'],
    'Region': ['Région', 'Región'],
    'Africa; regional projects count when African countries take part': ['Afrique ; les projets régionaux sont inclus lorsque des pays africains y participent', 'África; los proyectos regionales se incluyen cuando participan países africanos'],
    'Projects': ['Projets', 'Proyectos'],
    'Started in 2015 or later': ['Ayant débuté en 2015 ou après', 'Iniciados en 2015 o después'],
    'Subject': ['Sujet', 'Tema'],
    'Agriculture and food systems: crops, livestock, fisheries, agroforestry, food security, farm-based livelihoods': ['Agriculture et systèmes alimentaires : cultures, élevage, pêche, agroforesterie, sécurité alimentaire et moyens de subsistance agricoles', 'Agricultura y sistemas alimentarios: cultivos, ganadería, pesca, agroforestería, seguridad alimentaria y medios de vida agrícolas'],
    'Documents': ['Documents', 'Documentos'],
    'Completion reports, mid-term and final evaluations': ['Rapports d’achèvement, évaluations à mi-parcours et finales', 'Informes de finalización y evaluaciones intermedias y finales'],
    "Funders' sources": ['Sources des bailleurs', 'Fuentes de los financiadores'],
    'Adaptation Fund, African Development Bank, Global Environment Facility, Green Climate Fund, World Bank': ['Fonds pour l’adaptation, Banque africaine de développement, Fonds pour l’environnement mondial, Fonds vert pour le climat, Banque mondiale', 'Fondo de Adaptación, Banco Africano de Desarrollo, Fondo para el Medio Ambiente Mundial, Fondo Verde para el Clima, Banco Mundial'],
    'Who is behind it': ['Qui porte ce travail', 'Quién está detrás'],
    '[Partner statement: e.g. developed by the Alliance of Bioversity International and CIAT under CGIAR Climate Action, with support from the Gates Foundation.]': ['[Présentation des partenaires : par exemple, développé par l’Alliance de Bioversity International et du CIAT dans le cadre de CGIAR Climate Action, avec le soutien de la Fondation Gates.]', '[Presentación de los socios: por ejemplo, desarrollado por la Alianza de Bioversity International y el CIAT en el marco de CGIAR Climate Action, con el apoyo de la Fundación Gates.]'],
    'How to cite': ['Comment citer', 'Cómo citar'],
    '[Citation, year, version, DOI]': ['[Citation, année, version, DOI]', '[Cita, año, versión, DOI]'],
    'Contact': ['Contact', 'Contacto'],
    'Found an error or have a document we should read?': ['Vous avez repéré une erreur ou connaissez un document que nous devrions lire ?', '¿Ha encontrado un error o conoce un documento que deberíamos leer?'],
    'Versions': ['Versions', 'Versiones'],
    '18 Nov 2026': ['18 nov. 2026', '18 nov. 2026'],
    'Pilot dataset: 8 projects, 466 reported figures, 227 results. Not yet reviewed.': ['Jeu de données pilote : 8 projets, 466 chiffres rapportés, 227 résultats. Pas encore révisé.', 'Conjunto de datos piloto: 8 proyectos, 466 cifras comunicadas y 227 resultados. Aún no revisado.'],
    'Sources and credits': ['Sources et crédits', 'Fuentes y créditos'],
    'Project documents: the public reports of the funders listed above. Each record cites its document and page.': ['Documents de projet : les rapports publics des bailleurs indiqués ci-dessus. Chaque fiche cite son document et sa page.', 'Documentos de proyecto: los informes públicos de los financiadores indicados arriba. Cada registro cita su documento y página.'],
    'Sub-national boundaries: geoBoundaries, CC BY 4.0.': ['Limites infranationales : geoBoundaries, CC BY 4.0.', 'Límites subnacionales: geoBoundaries, CC BY 4.0.'],
    'Country outlines: Natural Earth, public domain.': ['Contours des pays : Natural Earth, domaine public.', 'Contornos de países: Natural Earth, dominio público.'],
    'Homepage image: [credit and licence]': ['Image de la page d’accueil : [crédit et licence]', 'Imagen de inicio: [crédito y licencia]'],

    'No results match these filters': ['Aucun résultat ne correspond à ces filtres', 'Ningún resultado coincide con estos filtros'],
    'Remove one of them, or start again.': ['Retirez un filtre ou recommencez.', 'Quite algún filtro o vuelva a empezar.'],
    'Clear all filters': ['Effacer tous les filtres', 'Borrar todos los filtros'],
    'Filters': ['Filtres', 'Filtros'],
    'Clear': ['Effacer', 'Borrar'],
    'Hide breakdowns, earlier values and other measures of a result': ['Masquer les ventilations, les valeurs antérieures et les autres mesures d’un résultat', 'Ocultar desgloses, valores anteriores y otras mediciones de un resultado'],
    'Total budget': ['Budget total', 'Presupuesto total'],
    'Funded by': ['Financé par', 'Financiado por'],
    'Implemented by': ['Mis en œuvre par', 'Ejecutado por'],
    'More about this project': ['En savoir plus sur ce projet', 'Más sobre este proyecto'],
    'Lead': ['Chef de file', 'Entidad principal'],
    'Status': ['Statut', 'Estado'],
    'Funding': ['Financement', 'Financiación'],
    'Beneficiaries': ['Bénéficiaires', 'Beneficiarios'],
    'Download CSV': ['Télécharger le CSV', 'Descargar CSV'],
    'Legend': ['Légende', 'Leyenda'],
    'Location-specific results': ['Résultats propres à un lieu', 'Resultados específicos de un lugar'],
    'All positions are approximate. Most places are shown at the centre of the county, district or region they name; the details card says how each place was positioned.': ['Toutes les positions sont approximatives. La plupart des lieux sont placés au centre du comté, district ou de la région qu’ils désignent ; la fiche détaillée précise comment chaque lieu a été positionné.', 'Todas las posiciones son aproximadas. La mayoría de los lugares se muestran en el centro del condado, distrito o región que nombran; la ficha de detalles indica cómo se ubicó cada lugar.'],
    'Project-wide results': ['Résultats à l’échelle du projet', 'Resultados de todo el proyecto'],
    'Same project': ['Même projet', 'Mismo proyecto'],
    'Area with project activity': ['Zone où un projet est actif', 'Zona con actividad del proyecto'],
    'Download selection': ['Télécharger la sélection', 'Descargar la selección'],
    'Full dataset': ['Jeu de données complet', 'Conjunto de datos completo'],
    'Skip tour': ['Passer la visite', 'Omitir recorrido'],
    'Previous step': ['Étape précédente', 'Paso anterior'],
    'Results table': ['Tableau des résultats', 'Tabla de resultados'],
    'Close the table': ['Fermer le tableau', 'Cerrar la tabla'],
    'Close details': ['Fermer les détails', 'Cerrar detalles'],
    'Map legend': ['Légende de la carte', 'Leyenda del mapa'],
    'Globe controls': ['Commandes du globe', 'Controles del globo'],
    'How to use this map': ['Comment utiliser cette carte', 'Cómo usar este mapa'],
    'Zoom in': ['Zoomer', 'Acercar'],
    'Zoom out': ['Dézoomer', 'Alejar'],
    'Zoom to an area: drag a box on the map (or hold Shift and drag)': ['Zoomer sur une zone : tracez un rectangle sur la carte (ou maintenez Maj et faites glisser)', 'Acercar a una zona: trace un recuadro en el mapa (o mantenga Mayús y arrastre)'],
    'Zoom to an area: drag a box (or Shift + drag)': ['Zoomer sur une zone : tracez un rectangle (ou Maj + glisser)', 'Acercar a una zona: trace un recuadro (o Mayús + arrastrar)'],
    'Back to the whole globe': ['Revenir au globe entier', 'Volver al globo completo'],
    'Globe of project locations. Drag to rotate, scroll to zoom, click a country to see its subdivisions.': ['Globe des lieux de projet. Faites glisser pour tourner, utilisez la molette pour zoomer et cliquez sur un pays pour voir ses subdivisions.', 'Globo de lugares de proyecto. Arrastre para girar, desplácese para acercar y haga clic en un país para ver sus subdivisiones.'],
    'Search results': ['Rechercher dans les résultats', 'Buscar en los resultados'],
    'irrigation, women, yield…': ['irrigation, femmes, rendement…', 'riego, mujeres, rendimiento…'],
    'Details': ['Détails', 'Detalles'],
    'Breadcrumb': ['Fil d’Ariane', 'Ruta de navegación'],

    'Welcome to the map': ['Bienvenue sur la carte', 'Bienvenido al mapa'],
    'Each point is a place named in a project evaluation or completion report. This short tour shows how to read the map and find what you need.': ['Chaque point correspond à un lieu cité dans une évaluation ou un rapport d’achèvement de projet. Cette courte visite vous montre comment lire la carte et trouver ce dont vous avez besoin.', 'Cada punto es un lugar mencionado en una evaluación o un informe de finalización de proyecto. Este breve recorrido explica cómo leer el mapa y encontrar lo que necesita.'],
    'Move around': ['Se déplacer', 'Desplazarse'],
    'Drag to turn the globe. Scroll, or use + and −, to zoom in and out. The globe button brings you back to the whole view.': ['Faites glisser pour tourner le globe. Utilisez la molette, ou les boutons + et −, pour zoomer et dézoomer. Le bouton du globe ramène à la vue d’ensemble.', 'Arrastre para girar el globo. Desplácese o use + y − para acercar y alejar. El botón del globo devuelve a la vista completa.'],
    'Zoom to an area': ['Zoomer sur une zone', 'Acercar a una zona'],
    'Hold Shift, or press the dashed-square button, then drag a box around a region. When you let go, the map zooms into it.': ['Maintenez la touche Maj ou appuyez sur le bouton en pointillés, puis tracez un rectangle autour d’une zone. Lorsque vous relâchez, la carte zoome sur cette zone.', 'Mantenga pulsada Mayús o presione el botón del recuadro discontinuo y trace un recuadro alrededor de una región. Al soltar, el mapa se acerca a ella.'],
    'Read the map': ['Lire la carte', 'Leer el mapa'],
    'Dark dots are places with their own results; bigger dots hold more results. Amber circles hold results reported for a whole project. Lines join the places of one project.': ['Les points foncés sont des lieux ayant leurs propres résultats ; les plus grands regroupent davantage de résultats. Les cercles ambrés correspondent aux résultats rapportés pour l’ensemble d’un projet. Les lignes relient les lieux d’un même projet.', 'Los puntos oscuros son lugares con resultados propios; los puntos más grandes contienen más resultados. Los círculos ámbar contienen resultados comunicados para todo un proyecto. Las líneas unen los lugares de un mismo proyecto.'],
    'Zoom into a country': ['Zoomer sur un pays', 'Acercar a un país'],
    'Click a country to fly in and see its counties, districts or regions. Here is Kenya: areas where a project works are tinted, and you can click each one.': ['Cliquez sur un pays pour vous en rapprocher et voir ses comtés, districts ou régions. Voici le Kenya : les zones où un projet intervient sont colorées et vous pouvez cliquer sur chacune.', 'Haga clic en un país para acercarse y ver sus condados, distritos o regiones. Aquí se muestra Kenia: las zonas donde trabaja un proyecto aparecen coloreadas y se puede hacer clic en cada una.'],
    'Open an area': ['Ouvrir une zone', 'Abrir una zona'],
    'Click a county, district or region and the map zooms into it. The card lists the places inside it and the results reported there.': ['Cliquez sur un comté, un district ou une région pour y zoomer. La fiche répertorie les lieux qu’il contient et les résultats qui y sont rapportés.', 'Haga clic en un condado, distrito o región y el mapa se acercará. La ficha enumera los lugares que contiene y los resultados comunicados allí.'],
    'See projects and results': ['Voir les projets et les résultats', 'Ver proyectos y resultados'],
    'Click a point or an area and a card opens on the right: the project, who funds and implements it, and every result with its evidence and source page. Its lines to the rest of the project light up.': ['Cliquez sur un point ou une zone : une fiche s’ouvre à droite avec le projet, ses bailleurs et responsables de mise en œuvre, ainsi que chaque résultat, ses données probantes et sa page source. Les lignes qui le relient au reste du projet s’illuminent.', 'Haga clic en un punto o una zona: se abrirá una ficha a la derecha con el proyecto, quién lo financia y ejecuta, y cada resultado con su evidencia y página de origen. Se resaltarán sus líneas hacia el resto del proyecto.'],
    'Filter the data': ['Filtrer les données', 'Filtrar los datos'],
    'Narrow the map by country, project, funder, result metric, evidence method and more. Tap a filter name to open it; Clear removes them all.': ['Affinez la carte par pays, projet, bailleur, indicateur de résultat, méthode de collecte des données probantes, etc. Appuyez sur le nom d’un filtre pour l’ouvrir ; « Effacer » les supprime tous.', 'Restrinja el mapa por país, proyecto, financiador, indicador de resultado, método de evidencia y otros criterios. Pulse el nombre de un filtro para abrirlo; «Borrar» los elimina todos.'],
    'Take the data with you': ['Emporter les données', 'Llevarse los datos'],
    'Download the results you are looking at as a spreadsheet (CSV), or the full dataset. Reopen this tour any time with the ? button.': ['Téléchargez les résultats affichés sous forme de feuille de calcul (CSV), ou téléchargez le jeu de données complet. Vous pouvez relancer cette visite à tout moment avec le bouton ?.', 'Descargue los resultados que está viendo como hoja de cálculo (CSV), o descargue el conjunto de datos completo. Puede volver a abrir este recorrido en cualquier momento con el botón ?.'],
    'Next': ['Suivant', 'Siguiente'],
    'Start exploring': ['Commencer à explorer', 'Empezar a explorar'],
    'Loading the projects…': ['Chargement des projets…', 'Cargando los proyectos…'],
    'The data could not be loaded.': ['Impossible de charger les données.', 'No se pudieron cargar los datos.'],

    'Search': ['Rechercher', 'Buscar'],
    'Any': ['Tous', 'Cualquiera'],
    'Result type': ['Type de résultat', 'Tipo de resultado'],
    'All': ['Tous', 'Todos'],
    'Output': ['Produit', 'Producto'],
    'Outcome': ['Effet', 'Efecto'],
    'Process': ['Processus', 'Proceso'],
    'Result scope': ['Portée du résultat', 'Alcance del resultado'],
    'All results': ['Tous les résultats', 'Todos los resultados'],
    'Country': ['Pays', 'País'],
    'All countries': ['Tous les pays', 'Todos los países'],
    'Project': ['Projet', 'Proyecto'],
    'All projects': ['Tous les projets', 'Todos los proyectos'],
    'Funder': ['Bailleur', 'Financiador'],
    'All funders': ['Tous les bailleurs', 'Todos los financiadores'],
    'Lead or implementing actor': ['Chef de file ou responsable de mise en œuvre', 'Entidad principal o ejecutora'],
    'All actors': ['Tous les acteurs', 'Todos los actores'],
    'Subsector': ['Sous-secteur', 'Subsector'],
    'All subsectors': ['Tous les sous-secteurs', 'Todos los subsectores'],
    'Result metric': ['Indicateur de résultat', 'Indicador de resultado'],
    'All metrics': ['Tous les indicateurs', 'Todos los indicadores'],
    'Evidence method': ['Méthode de collecte des données probantes', 'Método de evidencia'],
    'All methods': ['Toutes les méthodes', 'Todos los métodos'],
    'Direction of change': ['Sens du changement', 'Dirección del cambio'],
    'Any direction': ['Tous les sens', 'Cualquier dirección'],
    'Standalone results only': ['Résultats autonomes uniquement', 'Solo resultados independientes'],
    'On': ['Activé', 'Activado'],
    'Off': ['Désactivé', 'Desactivado'],
    'Location-specific': ['Propre à un lieu', 'Específico de un lugar'],
    'Project-wide': ['À l’échelle du projet', 'De todo el proyecto'],
    'Not reported': ['Non rapporté', 'No comunicado'],
    'Not stated': ['Non indiqué', 'No indicado'],
    'Stands on its own': ['Résultat autonome', 'Resultado independiente'],
    'Whole project': ['Ensemble du projet', 'Todo el proyecto'],
    'Africa': ['Afrique', 'África'],
    'Click a country': ['Cliquez sur un pays', 'Haga clic en un país'],
    'Zoom into a country to see its counties, districts or regions. Lines join the places of one project.': ['Zoomez sur un pays pour voir ses comtés, districts ou régions. Les lignes relient les lieux d’un même projet.', 'Acérquese a un país para ver sus condados, distritos o regiones. Las líneas unen los lugares de un mismo proyecto.'],
    'Countries · results': ['Pays · résultats', 'Países · resultados'],
    'Places here': ['Lieux dans cette zone', 'Lugares de esta zona'],
    'Country': ['Pays', 'País'],
    'Coordinates from the location register.': ['Coordonnées issues du registre des lieux.', 'Coordenadas del registro de lugares.'],
    'Approximate position near the project’s other places; not geocoded yet.': ['Position approximative à proximité des autres lieux du projet ; pas encore géocodée.', 'Posición aproximada cerca de otros lugares del proyecto; aún no geocodificada.'],
    'Project-wide results: reported for the whole project or country, not for one specific place.': ['Résultats à l’échelle du projet : rapportés pour l’ensemble du projet ou du pays, et non pour un lieu précis.', 'Resultados de todo el proyecto: comunicados para todo el proyecto o país, no para un lugar concreto.'],
    'Table open below': ['Tableau ouvert ci-dessous', 'Tabla abierta abajo'],
    'Positive change': ['Changement positif', 'Cambio positivo'],
    'Negative change': ['Changement négatif', 'Cambio negativo'],
    'Mixed change': ['Changement mitigé', 'Cambio mixto'],
    'No change': ['Aucun changement', 'Sin cambios'],
    'Direction not stated': ['Sens non indiqué', 'Dirección no indicada'],
    'Positive': ['Positif', 'Positivo'],
    'Negative': ['Négatif', 'Negativo'],
    'Mixed': ['Mitigé', 'Mixto'],
    'Level:': ['Niveau :', 'Nivel:'],
    'Year:': ['Année :', 'Año:'],
    'Baseline:': ['Valeur de référence :', 'Línea de base:'],
    'Target:': ['Cible :', 'Meta:'],
    'Measured by:': ['Mesuré par :', 'Medido mediante:'],
    'Source:': ['Source :', 'Fuente:'],
    'What was measured': ['Ce qui a été mesuré', 'Qué se midió'],
    'The kind of result, from the project vocabulary': ['Le type de résultat, selon le vocabulaire du projet', 'El tipo de resultado, según el vocabulario del proyecto'],
    'Result value': ['Valeur du résultat', 'Valor del resultado'],
    'The figure reported in the document': ['Le chiffre rapporté dans le document', 'La cifra comunicada en el documento'],
    'Unit (as written in the document)': ['Unité (telle qu’indiquée dans le document)', 'Unidad (tal como figura en el documento)'],
    'Unit of the result value, in the words of the document': ['Unité de la valeur du résultat, dans les termes du document', 'Unidad del valor del resultado, en los términos del documento'],
    'Standard unit': ['Unité normalisée', 'Unidad normalizada'],
    'The same unit in a standard form, for comparison across projects': ['La même unité sous une forme normalisée, pour comparer les projets', 'La misma unidad en formato normalizado, para comparar proyectos'],
    'Baseline (same unit)': ['Valeur de référence (même unité)', 'Línea de base (misma unidad)'],
    'Value before the project, in the same unit as the result': ['Valeur avant le projet, dans la même unité que le résultat', 'Valor anterior al proyecto, en la misma unidad que el resultado'],
    'Target (same unit)': ['Cible (même unité)', 'Meta (misma unidad)'],
    'Value the project aimed for, in the same unit as the result': ['Valeur visée par le projet, dans la même unité que le résultat', 'Valor que el proyecto pretendía alcanzar, en la misma unidad que el resultado'],
    'Year measured': ['Année de mesure', 'Año de medición'],
    'Year of the figure; the closing year when the document gives none': ['Année du chiffre ; année de clôture si le document n’en indique aucune', 'Año de la cifra; año de cierre cuando el documento no indica ninguno'],
    'Positive, negative, mixed or no change, as reported': ['Changement positif, négatif, mitigé ou nul, tel que rapporté', 'Cambio positivo, negativo, mixto o nulo, según lo comunicado'],
    'Result level': ['Niveau du résultat', 'Nivel del resultado'],
    'Output (what was delivered), outcome (change for people or land) or impact': ['Produit (ce qui a été livré), effet (changement pour les personnes ou les terres) ou impact', 'Producto (lo entregado), efecto (cambio para las personas o la tierra) o impacto'],
    'Place': ['Lieu', 'Lugar'],
    'Place the result is reported for; "whole project" when it is not tied to one place': ['Lieu pour lequel le résultat est rapporté ; « ensemble du projet » lorsqu’il n’est pas lié à un lieu', 'Lugar para el que se comunica el resultado; «todo el proyecto» cuando no está vinculado a un lugar'],
    'Statement': ['Énoncé', 'Enunciado'],
    'One sentence saying what the figure is': ['Une phrase indiquant ce que représente le chiffre', 'Una frase que indica qué representa la cifra'],
    'How it was measured': ['Méthode de mesure', 'Cómo se midió'],
    'Evidence behind the figure': ['Données probantes à l’appui du chiffre', 'Evidencia que sustenta la cifra'],
    'Source (document, PDF page)': ['Source (document, page du PDF)', 'Fuente (documento, página del PDF)'],
    'Where the figure is printed': ['Emplacement du chiffre dans la source', 'Dónde aparece impresa la cifra'],
    'Relation to other results': ['Lien avec d’autres résultats', 'Relación con otros resultados'],
    'A part, another measure or an earlier value of another result; otherwise it stands on its own': ['Une partie, une autre mesure ou une valeur antérieure d’un autre résultat ; sinon, le résultat est autonome', 'Una parte, otra medición o un valor anterior de otro resultado; de lo contrario, es independiente'],
    'Project code and title': ['Code et titre du projet', 'Código y título del proyecto'],
    'Intervention': ['Intervention', 'Intervención'],
    'The line of work that produced the result (full text on hover)': ['Le domaine d’intervention ayant produit le résultat (texte complet au survol)', 'La línea de trabajo que produjo el resultado (texto completo al pasar el cursor)'],
    'Result ID': ['Identifiant du résultat', 'Identificador del resultado'],
    'Identifier of the row in the dataset': ['Identifiant de la ligne dans le jeu de données', 'Identificador de la fila en el conjunto de datos'],
    'Values are as reported in the documents. Baseline and target are in the same unit as the result value. "Not stated" means the document does not give it. Scroll sideways for more columns.': ['Les valeurs sont celles rapportées dans les documents. La valeur de référence et la cible utilisent la même unité que le résultat. « Non indiqué » signifie que le document ne fournit pas l’information. Faites défiler horizontalement pour voir les autres colonnes.', 'Los valores son los comunicados en los documentos. La línea de base y la meta están en la misma unidad que el valor del resultado. «No indicado» significa que el documento no proporciona el dato. Desplácese horizontalmente para ver más columnas.'],
    'unit not stated': ['unité non indiquée', 'unidad no indicada']
  };

  var VALUES = {
    'Morocco': ['Maroc', 'Marruecos'], 'Ethiopia': ['Éthiopie', 'Etiopía'], 'Comoros': ['Comores', 'Comoras'],
    'Kenya': ['Kenya', 'Kenia'], 'Malawi': ['Malawi', 'Malaui'], 'The Gambia': ['Gambie', 'Gambia'],
    'Gambia': ['Gambie', 'Gambia'], 'Eritrea': ['Érythrée', 'Eritrea'], 'Namibia': ['Namibie', 'Namibia'],
    'County': ['comté', 'condado'], 'District': ['district', 'distrito'], 'Region': ['région', 'región'],
    'Province': ['province', 'provincia'], 'Island': ['île', 'isla'], 'Local government area': ['zone d’administration locale', 'área de gobierno local'],
    'counties': ['comtés', 'condados'], 'districts': ['districts', 'distritos'], 'regions': ['régions', 'regiones'],
    'provinces': ['provinces', 'provincias'], 'islands': ['îles', 'islas'], 'local government areas': ['zones d’administration locale', 'áreas de gobierno local'],

    'agri-food': ['agroalimentaire', 'agroalimentario'], 'cross-cutting': ['transversal', 'transversal'],
    'farming system-crop': ['système agricole — cultures', 'sistema agrícola — cultivos'],
    'farming system-mixed': ['système agricole mixte', 'sistema agrícola mixto'], 'land use': ['utilisation des terres', 'uso de la tierra'],
    'not specified': ['non précisé', 'no especificado'], 'unclear/not stated': ['incertain/non indiqué', 'no claro/no indicado'],
    'before-after / baseline-endline survey': ['enquête avant-après / référence-fin de projet', 'encuesta antes-después / línea de base-final'],
    'case study': ['étude de cas', 'estudio de caso'], 'mixed methods': ['méthodes mixtes', 'métodos mixtos'],
    'qualitative (interviews, FGDs, case study)': ['qualitatif (entretiens, groupes de discussion, étude de cas)', 'cualitativo (entrevistas, grupos focales, estudio de caso)'],
    'quasi-experimental (comparison group)': ['quasi-expérimental (groupe de comparaison)', 'cuasiexperimental (grupo de comparación)'],
    'remote sensing / modelling': ['télédétection / modélisation', 'teledetección / modelización'],
    'routine monitoring data': ['données de suivi courant', 'datos de seguimiento rutinario'],
    'routine monitoring data; before-after / baseline-endline survey': ['données de suivi courant ; enquête avant-après / référence-fin de projet', 'datos de seguimiento rutinario; encuesta antes-después / línea de base-final'],
    'positive': ['positif', 'positivo'], 'negative': ['négatif', 'negativo'], 'mixed': ['mitigé', 'mixto'], 'no change': ['aucun changement', 'sin cambios'],
    'output': ['produit', 'producto'], 'outcome': ['effet', 'efecto'], 'process': ['processus', 'proceso'],
    'earlier value of': ['valeur antérieure de', 'valor anterior de'], 'other measure of': ['autre mesure de', 'otra medición de'], 'part of': ['partie de', 'parte de'],

    'GHG emissions reduced/avoided': ['émissions de GES réduites/évitées', 'emisiones de GEI reducidas/evitadas'],
    'access to drinking or domestic water': ['accès à l’eau potable ou domestique', 'acceso a agua potable o doméstica'],
    'association members reached': ['membres d’associations touchés', 'miembros de asociaciones alcanzados'],
    'beneficiary satisfaction': ['satisfaction des bénéficiaires', 'satisfacción de los beneficiarios'],
    'cooperatives reached': ['coopératives touchées', 'cooperativas alcanzadas'], 'crop yield': ['rendement des cultures', 'rendimiento de los cultivos'],
    'direct beneficiaries': ['bénéficiaires directs', 'beneficiarios directos'], 'farmer groups reached': ['groupes d’agriculteurs touchés', 'grupos de agricultores alcanzados'],
    'farmers adopting practices or technologies': ['agriculteurs adoptant des pratiques ou technologies', 'agricultores que adoptan prácticas o tecnologías'],
    'groundwater level': ['niveau des eaux souterraines', 'nivel de las aguas subterráneas'], 'household income': ['revenu des ménages', 'ingresos de los hogares'],
    'infrastructure built/rehabilitated': ['infrastructures construites/réhabilitées', 'infraestructura construida/rehabilitada'],
    'inputs or equipment distributed': ['intrants ou équipements distribués', 'insumos o equipos distribuidos'], 'irrigated land': ['terres irriguées', 'tierras irrigadas'],
    'jobs created': ['emplois créés', 'empleos creados'], 'land restored': ['terres restaurées', 'tierras restauradas'],
    'land under climate-smart practices': ['terres sous pratiques intelligentes face au climat', 'tierras bajo prácticas climáticamente inteligentes'],
    'livestock distributed': ['bétail distribué', 'ganado distribuido'], 'livestock or fish productivity': ['productivité de l’élevage ou de la pêche', 'productividad ganadera o pesquera'],
    'local institutions established or strengthened': ['institutions locales créées ou renforcées', 'instituciones locales creadas o fortalecidas'],
    'other': ['autre', 'otro'], 'people covered by insurance': ['personnes couvertes par une assurance', 'personas cubiertas por seguros'],
    'people reached by awareness raising': ['personnes touchées par la sensibilisation', 'personas alcanzadas mediante sensibilización'],
    'people trained': ['personnes formées', 'personas capacitadas'], 'people with access to information or advisory services': ['personnes ayant accès à l’information ou à des services de conseil', 'personas con acceso a información o servicios de asesoramiento'],
    'policies or regulations adopted': ['politiques ou réglementations adoptées', 'políticas o reglamentos adoptados'],
    'producer organizations reached': ['organisations de producteurs touchées', 'organizaciones de productores alcanzadas'],
    'seed or breeding stock produced': ['semences ou reproducteurs produits', 'semillas o material reproductor producidos'],
    'smallholder farmers reached': ['petits exploitants agricoles touchés', 'pequeños agricultores alcanzados'],
    'studies and knowledge products produced': ['études et produits de connaissance produits', 'estudios y productos de conocimiento elaborados'],
    'sub-projects or enterprises supported': ['sous-projets ou entreprises soutenus', 'subproyectos o empresas apoyados'],
    'total production': ['production totale', 'producción total'], 'vulnerable households reached': ['ménages vulnérables touchés', 'hogares vulnerables alcanzados'],
    'water harvested/stored': ['eau collectée/stockée', 'agua captada/almacenada'], 'water productivity or efficiency': ['productivité ou efficacité de l’eau', 'productividad o eficiencia del agua'],
    'women beneficiaries': ['femmes bénéficiaires', 'mujeres beneficiarias'],

    'completed': ['achevé', 'finalizado'], 'ongoing': ['en cours', 'en curso'], 'national': ['national', 'nacional'], 'sub-national': ['infranational', 'subnacional'],
    'grant': ['subvention', 'subvención'], 'loan': ['prêt', 'préstamo'], 'grant; loan': ['subvention ; prêt', 'subvención; préstamo'],
    'grant; other': ['subvention ; autre', 'subvención; otro'], 'loan; grant': ['prêt ; subvention', 'préstamo; subvención'], 'loan; other': ['prêt ; autre', 'préstamo; otro'],
    'completion report': ['rapport d’achèvement', 'informe de finalización'], 'final/terminal evaluation': ['évaluation finale/terminale', 'evaluación final/terminal'],
    'mid-term evaluation': ['évaluation à mi-parcours', 'evaluación de mitad de período'],
    'community': ['communauté', 'comunidad'], 'household': ['ménage', 'hogar'], 'low-income households': ['ménages à faible revenu', 'hogares de bajos ingresos'],
    'vulnerable population': ['population vulnérable', 'población vulnerable'], 'producer': ['producteur', 'productor'], 'women': ['femmes', 'mujeres'],
    'children': ['enfants', 'niños'], 'farmer group': ['groupe d’agriculteurs', 'grupo de agricultores'], 'youth': ['jeunes', 'jóvenes'],
    'pastoralist/herder': ['pasteur/éleveur', 'pastor/ganadero'], 'smallholder farmer': ['petit exploitant agricole', 'pequeño agricultor'],
    'female-headed households': ['ménages dirigés par une femme', 'hogares encabezados por mujeres'], 'subsistence farmer': ['agriculteur de subsistance', 'agricultor de subsistencia'],
    'marginalized group': ['groupe marginalisé', 'grupo marginado'], 'producer organization': ['organisation de producteurs', 'organización de productores'],
    'cooperative': ['coopérative', 'cooperativa'], 'people with disabilities': ['personnes handicapées', 'personas con discapacidad'], 'elderly': ['personnes âgées', 'personas mayores'],
    'basin': ['bassin', 'cuenca'], 'country': ['pays', 'país'], 'county': ['comté', 'condado'], 'demonstration site': ['site de démonstration', 'sitio de demostración'],
    'district': ['district', 'distrito'], 'institute': ['institut', 'instituto'], 'locality': ['localité', 'localidad'], 'oasis/perimeter': ['oasis/périmètre', 'oasis/perímetro'],
    'project-wide': ['ensemble du projet', 'todo el proyecto'], 'province': ['province', 'provincia'], 'region': ['région', 'región'], 'road': ['route', 'carretera'],
    'territorial collectivity (CT)': ['collectivité territoriale (CT)', 'colectividad territorial (CT)'],

    'Adaptation Fund': ['Fonds pour l’adaptation', 'Fondo de Adaptación'], 'African Development Bank': ['Banque africaine de développement', 'Banco Africano de Desarrollo'],
    'Green Climate Fund': ['Fonds vert pour le climat', 'Fondo Verde para el Clima'], 'World Bank (IDA)': ['Banque mondiale (IDA)', 'Banco Mundial (AIF)'],
    'GEF-LDCF via UNDP': ['FEM-FPMA via le PNUD', 'FMAM-FPMA a través del PNUD'], 'GEF-LDCF via UNEP': ['FEM-FPMA via le PNUE', 'FMAM-FPMA a través del PNUMA']
  };

  var PROJECTS = {
    P0010: ['Adaptation au changement climatique dans les zones oasiennes (PACCZO)', 'Adaptación al cambio climático en zonas de oasis (PACCZO)'],
    P0011: ['Renforcement des capacités d’adaptation des communautés par la mise à l’échelle des meilleures pratiques', 'Fortalecimiento de la capacidad de adaptación de las comunidades mediante la ampliación de buenas prácticas'],
    P0012: ['Renforcement de la résilience climatique par la réhabilitation des bassins versants et des forêts et par des moyens de subsistance adaptés', 'Fortalecimiento de la resiliencia climática mediante cuencas y bosques rehabilitados y medios de vida adaptativos'],
    P0013: ['Projet d’agriculture intelligente face au climat au Kenya', 'Proyecto de agricultura climáticamente inteligente de Kenia'],
    P0014: ['Projet de relèvement d’urgence après les inondations au Malawi', 'Proyecto de recuperación de emergencia tras las inundaciones en Malaui'],
    P0015: ['Projet du programme stratégique pour la résilience climatique', 'Proyecto del Programa Estratégico para la Resiliencia Climática'],
    P0016: ['Programme de résilience à la sécheresse et de moyens de subsistance durables (DRSLP-IV)', 'Programa de resiliencia ante la sequía y medios de vida sostenibles (DRSLP-IV)'],
    P0017: ['Agriculture résiliente au climat dans les régions agricoles du nord (CRAVE)', 'Agricultura resiliente al clima en las regiones agrícolas del norte (CRAVE)']
  };

  var SEARCH_ALIASES = {
    fr: {
      femmes: 'women', femme: 'women', rendement: 'yield', irrigation: 'irrigation', eau: 'water',
      terres: 'land', agriculteurs: 'farmers', bénéficiaires: 'beneficiaries', formation: 'trained',
      emplois: 'jobs', revenu: 'income', élevage: 'livestock', sécheresse: 'drought', inondation: 'flood'
    },
    es: {
      mujeres: 'women', mujer: 'women', rendimiento: 'yield', riego: 'irrigation', agua: 'water',
      tierras: 'land', agricultores: 'farmers', beneficiarios: 'beneficiaries', capacitación: 'trained',
      empleos: 'jobs', ingresos: 'income', ganado: 'livestock', sequía: 'drought', inundación: 'flood'
    }
  };

  var current = getInitialLanguage();
  var originals = new WeakMap();
  var lastApplied = new WeakMap();
  var attrOriginals = new WeakMap();
  var attrLastApplied = new WeakMap();
  var pending = new Set();
  var scheduled = false;

  function getInitialLanguage() {
    var param = '';
    try { param = new URL(window.location.href).searchParams.get('lang') || ''; } catch (e) {}
    if (LANGS.indexOf(param) >= 0) return param;
    try {
      var stored = window.localStorage.getItem(STORAGE_KEY);
      if (LANGS.indexOf(stored) >= 0) return stored;
    } catch (e2) {}
    return 'en';
  }

  function pairValue(table, key, lang) {
    if (lang === 'en' || !table[key]) return key;
    return table[key][LANG_INDEX[lang]] || key;
  }

  function valueTranslation(value, lang) {
    if (lang === 'en' || value === null || value === undefined) return value;
    var raw = String(value);
    if (VALUES[raw]) return pairValue(VALUES, raw, lang);
    var lower = raw.toLocaleLowerCase('en');
    var key = Object.keys(VALUES).find(function (item) { return item.toLocaleLowerCase('en') === lower; });
    if (key) {
      var result = pairValue(VALUES, key, lang);
      if (/^[A-ZÀ-ÖØ-Þ]/.test(raw)) result = result.charAt(0).toLocaleUpperCase(lang) + result.slice(1);
      return result;
    }
    if (raw.indexOf(';') >= 0) {
      return raw.split(/\s*;\s*/).map(function (part) { return valueTranslation(part, lang); }).join(lang === 'fr' ? ' ; ' : '; ');
    }
    return raw;
  }

  function formatNumber(number, lang) {
    return Number(number).toLocaleString(lang === 'fr' ? 'fr-FR' : lang === 'es' ? 'es-ES' : 'en-US');
  }

  function plural(number, one, many) { return Number(number) === 1 ? one : many; }

  function dynamicTranslation(text, lang) {
    if (lang === 'en') return text;
    var match;
    if ((match = text.match(/^(\d+) active$/))) return lang === 'fr' ? match[1] + ' ' + plural(match[1], 'actif', 'actifs') : match[1] + ' ' + plural(match[1], 'activo', 'activos');
    if ((match = text.match(/^(\d+) of (\d+)$/))) return lang === 'fr' ? match[1] + ' sur ' + match[2] : match[1] + ' de ' + match[2];
    if ((match = text.match(/^(.+) \((\d+)\)$/))) return valueTranslation(match[1], lang) + ' (' + match[2] + ')';
    if ((match = text.match(/^Download these (\d+) results \(CSV\)$/))) return lang === 'fr' ? 'Télécharger ces ' + match[1] + ' résultats (CSV)' : 'Descargar estos ' + match[1] + ' resultados (CSV)';
    if ((match = text.match(/^Show these (\d+) results as a table$/))) return lang === 'fr' ? 'Afficher ces ' + match[1] + ' résultats dans un tableau' : 'Mostrar estos ' + match[1] + ' resultados en una tabla';
    if ((match = text.match(/^Results (at this place|in .+)$/))) return lang === 'fr' ? 'Résultats ' + (match[1] === 'at this place' ? 'dans ce lieu' : match[1].replace(/^in /, 'dans ')) : 'Resultados ' + (match[1] === 'at this place' ? 'en este lugar' : match[1].replace(/^in /, 'en '));
    if ((match = text.match(/^Level: (.+)$/))) return (lang === 'fr' ? 'Niveau : ' : 'Nivel: ') + valueTranslation(match[1], lang);
    if ((match = text.match(/^Year: (.+)$/))) return (lang === 'fr' ? 'Année : ' : 'Año: ') + match[1];
    if ((match = text.match(/^Baseline: (.+)$/))) return (lang === 'fr' ? 'Valeur de référence : ' : 'Línea de base: ') + match[1];
    if ((match = text.match(/^Target: (.+)$/))) return (lang === 'fr' ? 'Cible : ' : 'Meta: ') + match[1];
    if ((match = text.match(/^Measured by: (.+)$/))) return (lang === 'fr' ? 'Mesuré par : ' : 'Medido mediante: ') + valueTranslation(match[1], lang);
    if ((match = text.match(/^Source: (.+)$/))) return (lang === 'fr' ? 'Source : ' : 'Fuente: ') + match[1];
    if ((match = text.match(/^Whole project \((.+)\)$/))) return (lang === 'fr' ? 'Ensemble du projet (' : 'Todo el proyecto (') + valueTranslation(match[1], lang) + ')';
    if ((match = text.match(/^(\d+) places: (.+) and (\d+) more$/))) return lang === 'fr' ? match[1] + ' lieux : ' + match[2] + ' et ' + match[3] + ' autres' : match[1] + ' lugares: ' + match[2] + ' y ' + match[3] + ' más';
    if ((match = text.match(/^Results table · (.+)$/))) return (lang === 'fr' ? 'Tableau des résultats · ' : 'Tabla de resultados · ') + match[1];
    if ((match = text.match(/^(\d+) rows: (\d+) results that stand on their own, and (\d+) parts, other measures or earlier values of another result \(shaded\)$/))) return lang === 'fr' ? match[1] + ' lignes : ' + match[2] + ' résultats autonomes et ' + match[3] + ' parties, autres mesures ou valeurs antérieures d’un autre résultat (ombrées)' : match[1] + ' filas: ' + match[2] + ' resultados independientes y ' + match[3] + ' partes, otras mediciones o valores anteriores de otro resultado (sombreados)';
    if ((match = text.match(/^(\d+) result(s?), each standing on its own$/))) return lang === 'fr' ? match[1] + ' ' + plural(match[1], 'résultat autonome', 'résultats autonomes') : match[1] + ' ' + plural(match[1], 'resultado independiente', 'resultados independientes');
    if ((match = text.match(/^(\d+) places$/))) return lang === 'fr' ? match[1] + ' lieux' : match[1] + ' lugares';
    if ((match = text.match(/^(Part of|Other measure of|Earlier value of) (.+)$/))) return valueTranslation(match[1].toLocaleLowerCase(), lang) + ' ' + match[2];
    if ((match = text.match(/^(.+) · (Completed|Ongoing)$/))) return match[1] + ' · ' + valueTranslation(match[2], lang);
    if ((match = text.match(/^(Completed|Ongoing), (national|sub-national) scale$/))) return valueTranslation(match[1], lang) + (lang === 'fr' ? ', échelle ' : ', escala ') + valueTranslation(match[2], lang);
    if ((match = text.match(/^(Completion report|Final\/terminal evaluation|Mid-term evaluation)( · .+)?$/))) return valueTranslation(match[1], lang) + (match[2] || '');
    if ((match = text.match(/^(\d+) results reported for places in this (.+)\.$/))) return lang === 'fr' ? match[1] + ' résultats rapportés pour des lieux de cette ' + valueTranslation(match[2], lang) + '.' : match[1] + ' resultados comunicados para lugares de esta ' + valueTranslation(match[2], lang) + '.';
    if ((match = text.match(/^No results in the current selection for this (.+)\.$/))) return lang === 'fr' ? 'Aucun résultat de la sélection actuelle pour cette ' + valueTranslation(match[1], lang) + '.' : 'No hay resultados en la selección actual para esta ' + valueTranslation(match[1], lang) + '.';
    if ((match = text.match(/^(\d+) of (\d+) (.+) have project activity\. Click one on the globe or in the list\.$/))) return lang === 'fr' ? match[1] + ' ' + valueTranslation(match[3], lang) + ' sur ' + match[2] + ' présentent une activité de projet. Cliquez sur l’une d’elles sur le globe ou dans la liste.' : match[1] + ' de ' + match[2] + ' ' + valueTranslation(match[3], lang) + ' tienen actividad de proyecto. Haga clic en una en el globo o en la lista.';
    if ((match = text.match(/^(.+) · results$/))) return valueTranslation(match[1], lang) + (lang === 'fr' ? ' · résultats' : ' · resultados');
    if ((match = text.match(/^Inside (.+); exact position not geocoded yet\.$/))) return lang === 'fr' ? 'À l’intérieur de ' + match[1] + ' ; position exacte pas encore géocodée.' : 'Dentro de ' + match[1] + '; posición exacta aún no geocodificada.';
    if ((match = text.match(/^Shown at the centre of this (.+)\.$/))) return lang === 'fr' ? 'Affiché au centre de cette ' + valueTranslation(match[1], lang) + '.' : 'Mostrado en el centro de esta ' + valueTranslation(match[1], lang) + '.';
    if ((match = text.match(/^(.+): open on the globe$/))) return (lang === 'fr' ? translateEmbeddedNames(match[1], lang) + ' : ouvrir sur le globe' : translateEmbeddedNames(match[1], lang) + ': abrir en el globo');
    if ((match = text.match(/^(.+): (\d+) project-wide result(s?) \((.+)\)$/))) return lang === 'fr' ? valueTranslation(match[1], lang) + ' : ' + match[2] + ' ' + plural(match[2], 'résultat à l’échelle du projet', 'résultats à l’échelle du projet') + ' (' + match[4] + ')' : valueTranslation(match[1], lang) + ': ' + match[2] + ' ' + plural(match[2], 'resultado de todo el proyecto', 'resultados de todo el proyecto') + ' (' + match[4] + ')';
    if ((match = text.match(/^(.+), (.+) — (\d+) location-specific result(s?)$/))) return lang === 'fr' ? match[1] + ', ' + valueTranslation(match[2], lang) + ' — ' + match[3] + ' ' + plural(match[3], 'résultat propre à ce lieu', 'résultats propres à ce lieu') : match[1] + ', ' + valueTranslation(match[2], lang) + ' — ' + match[3] + ' ' + plural(match[3], 'resultado específico del lugar', 'resultados específicos del lugar');
    if ((match = text.match(/^(.+) scale$/))) return lang === 'fr' ? 'échelle ' + valueTranslation(match[1], lang) : 'escala ' + valueTranslation(match[1], lang);
    return valueTranslation(text, lang);
  }

  function translateCore(text, lang) {
    if (lang === 'en' || !text) return text;
    if (TEXT[text]) return pairValue(TEXT, text, lang);
    var code = Object.keys(PROJECTS).find(function (key) {
      return text === PROJECT_SOURCE[key] || text.indexOf(key + ' · ' + PROJECT_SOURCE[key]) >= 0;
    });
    if (code && text === PROJECT_SOURCE[code]) return PROJECTS[code][LANG_INDEX[lang]];
    if (code) return text.replace(PROJECT_SOURCE[code], PROJECTS[code][LANG_INDEX[lang]]);
    return dynamicTranslation(text, lang);
  }

  var PROJECT_SOURCE = {
    P0010: 'Adaptation to Climate Change in Oasis Zones (PACCZO)',
    P0011: 'Enhancing adaptive capacity of communities by up-scaling best practices',
    P0012: 'Building Climate Resilience through Rehabilitated Watersheds, Forests and Adaptive Livelihoods',
    P0013: 'Kenya Climate Smart Agriculture Project',
    P0014: 'Malawi Floods Emergency Recovery Project',
    P0015: 'Strategic Program on Climate Resilience Project',
    P0016: 'Drought Resilience and Sustainable Livelihoods Programme (DRSLP-IV)',
    P0017: 'Climate Resilient Agriculture in northern crop-growing regions (CRAVE)'
  };

  function translateEmbeddedNames(text, lang) {
    var result = text;
    Object.keys(PROJECT_SOURCE).forEach(function (code) {
      result = result.split(PROJECT_SOURCE[code]).join(PROJECTS[code][LANG_INDEX[lang]]);
    });
    ['Morocco', 'Ethiopia', 'Comoros', 'Kenya', 'Malawi', 'The Gambia', 'Eritrea', 'Namibia'].forEach(function (name) {
      result = result.split(name).join(pairValue(VALUES, name, lang));
    });
    return result;
  }

  function translatePreservingWhitespace(raw, lang) {
    if (!raw || !raw.trim()) return raw;
    var leading = raw.match(/^\s*/)[0];
    var trailing = raw.match(/\s*$/)[0];
    var core = raw.slice(leading.length, raw.length - trailing.length || raw.length);
    return leading + translateCore(core, lang) + trailing;
  }

  function shouldSkip(node) {
    var element = node.nodeType === 1 ? node : node.parentElement;
    return !element || !!element.closest('script, style, noscript, textarea, code, pre, [data-ai-no-translate]');
  }

  function applyTextNode(node) {
    if (shouldSkip(node)) return;
    var last = lastApplied.get(node);
    if (!originals.has(node) || node.data !== last) originals.set(node, node.data);
    var next = translatePreservingWhitespace(originals.get(node), current);
    lastApplied.set(node, next);
    if (node.data !== next) node.data = next;
  }

  function applyAttributes(element) {
    if (shouldSkip(element)) return;
    var attrs = ['aria-label', 'title', 'placeholder'];
    var base = attrOriginals.get(element) || {};
    var last = attrLastApplied.get(element) || {};
    attrs.forEach(function (name) {
      if (!element.hasAttribute(name)) return;
      var present = element.getAttribute(name);
      if (!(name in base) || present !== last[name]) base[name] = present;
      var next = translateCore(base[name], current);
      last[name] = next;
      if (present !== next) element.setAttribute(name, next);
    });
    attrOriginals.set(element, base);
    attrLastApplied.set(element, last);
  }

  function apply(root) {
    if (!root) return;
    if (root.nodeType === 3) {
      applyTextNode(root);
      return;
    }
    if (root.nodeType !== 1 && root.nodeType !== 9 && root.nodeType !== 11) return;
    if (root.nodeType === 1) applyAttributes(root);
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
    var node;
    while ((node = walker.nextNode())) {
      if (node.nodeType === 3) applyTextNode(node); else applyAttributes(node);
    }
    document.documentElement.lang = current;
  }

  function schedule(root) {
    pending.add(root && root.nodeType ? root : document.documentElement);
    if (scheduled) return;
    scheduled = true;
    window.requestAnimationFrame(function () {
      scheduled = false;
      var roots = Array.from(pending);
      pending.clear();
      roots.forEach(apply);
    });
  }

  function languageLabel(lang) {
    return { en: 'English', fr: 'Français', es: 'Español' }[lang];
  }

  function switchLabel() {
    return current === 'fr' ? 'Langue' : current === 'es' ? 'Idioma' : 'Language';
  }

  function updateSwitch() {
    var group = document.querySelector('.ai-lang-switch');
    if (!group) return;
    group.setAttribute('aria-label', switchLabel());
    group.querySelectorAll('button[data-lang]').forEach(function (button) {
      var active = button.getAttribute('data-lang') === current;
      button.setAttribute('aria-pressed', active ? 'true' : 'false');
      button.classList.toggle('is-active', active);
    });
  }

  function mountSwitch() {
    var group = document.querySelector('.ai-lang-switch');
    var header = document.querySelector('header');
    if (!header) return;
    if (!group) {
      group = document.createElement('div');
      group.className = 'ai-lang-switch';
      group.setAttribute('role', 'group');
      LANGS.forEach(function (lang) {
        var button = document.createElement('button');
        button.type = 'button';
        button.setAttribute('data-lang', lang);
        button.setAttribute('aria-label', languageLabel(lang));
        button.title = languageLabel(lang);
        button.textContent = lang.toUpperCase();
        group.appendChild(button);
      });
      header.appendChild(group);
    }
    group.querySelectorAll('button[data-lang]').forEach(function (button) {
      if (button.getAttribute('data-ai-lang-bound') === 'true') return;
      button.setAttribute('data-ai-lang-bound', 'true');
      button.addEventListener('click', function () { setLanguage(button.getAttribute('data-lang')); });
    });
    updateSwitch();
  }

  function mountStyles() {
    if (document.getElementById('ai-language-styles')) return;
    var style = document.createElement('style');
    style.id = 'ai-language-styles';
    style.textContent = [
      'header>a:first-child{order:1}header>nav{order:2;margin-left:auto}.ai-lang-switch{order:3}',
      '.ai-lang-switch{display:inline-flex;align-items:center;gap:2px;padding:3px;border:1px solid #D5DAEA;border-radius:999px;background:#F4F6FB;box-shadow:0 1px 0 rgba(14,23,71,.04)}',
      '.ai-lang-switch button{min-width:38px;height:32px;padding:0 9px;border:0;border-radius:999px;background:transparent;color:#4B5478;font-family:"IBM Plex Mono",Menlo,monospace;font-size:11px;font-weight:500;letter-spacing:.04em;cursor:pointer;transition:background .16s,color .16s,box-shadow .16s}',
      '.ai-lang-switch button:hover{color:#0E1747;background:#FFFFFF}',
      '.ai-lang-switch button.is-active{background:#0E1747;color:#FFFFFF;box-shadow:0 2px 7px rgba(14,23,71,.2)}',
      '.ai-lang-switch button:focus-visible{outline:2px solid #1D3BA8;outline-offset:2px}',
      '@media(max-width:760px){header{column-gap:12px!important}header>nav{order:3;width:100%;margin-left:0;gap:4px 16px!important}.ai-lang-switch{order:2;margin-left:auto}.ai-lang-switch button{min-width:34px;padding:0 7px}}',
      '@media(max-width:480px){header>nav{font-size:13px!important;gap:2px 11px!important}.ai-lang-switch button{min-width:31px;height:30px;padding:0 5px;font-size:10px}}',
      '@media(max-width:350px){header>a:first-child span{font-size:21px!important}.ai-lang-switch{margin-left:0}}'
    ].join('');
    document.head.appendChild(style);
  }

  function setLanguage(lang) {
    if (LANGS.indexOf(lang) < 0) return;
    current = lang;
    try { window.localStorage.setItem(STORAGE_KEY, lang); } catch (e) {}
    apply(document.documentElement);
    updateSwitch();
    window.dispatchEvent(new CustomEvent('ai-language-change', { detail: { language: lang } }));
  }

  function init() {
    try { window.localStorage.setItem(STORAGE_KEY, current); } catch (e) {}
    mountStyles();
    mountSwitch();
    apply(document.documentElement);
    updateSwitch();
    var observer = new MutationObserver(function (records) {
      records.forEach(function (record) {
        if (record.type === 'characterData') schedule(record.target);
        if (record.type === 'attributes') schedule(record.target);
        if (record.type === 'childList') record.addedNodes.forEach(schedule);
      });
    });
    observer.observe(document.documentElement, {
      subtree: true, childList: true, characterData: true, attributes: true,
      attributeFilter: ['aria-label', 'title', 'placeholder']
    });
  }

  window.AI18N = {
    getLanguage: function () { return current; },
    setLanguage: setLanguage,
    text: function (value) { return translateCore(value, current); },
    value: function (value) { return valueTranslation(value, current); },
    projectTitle: function (code, fallback) { return current === 'en' || !PROJECTS[code] ? fallback : PROJECTS[code][LANG_INDEX[current]]; },
    country: function (value) { return valueTranslation(value, current); },
    searchQuery: function (query) {
      var source = String(query || '').toLocaleLowerCase(current);
      var aliases = SEARCH_ALIASES[current] || {};
      return source.split(/\s+/).map(function (word) { return aliases[word] || word; }).join(' ');
    },
    formatNumber: function (number, options) { return Number(number).toLocaleString(current === 'fr' ? 'fr-FR' : current === 'es' ? 'es-ES' : 'en-US', options || {}); },
    apply: apply
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
