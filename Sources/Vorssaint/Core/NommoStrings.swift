// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Jater

import Foundation

struct NommoFeatureStrings {
    let title: String
    let hubDescription: String
    let panelDescription: String
    let showInPanel: String
    let notConnected: String
    let connected: String
    let firmwareFormat: String
    let subwoofer: String
    let equalizer: String
    let builtInGroup: String
    let builtInCaption: String
    let myEQGroup: String
    let presetGame: String
    let presetMusic: String
    let presetMovie: String
    let presetFlat: String
    let otherCustom: String
    let unknownMode: String
    let editCurve: String
    let editCaption: String
    let restoreSuggestion: String
    let autoStandby: String
    let autoStandbyCaption: String
    let standbyDelay: String
    let minutesFormat: String
    let noReply: String
    let lighting: String
    let lightingOff: String
    let lightingSpectrum: String
    let lightingCaption: String
    let lightingSolid: String
    let lightingColor: String
    let brightness: String
    let addColor: String
    let deleteColor: String
    let deleteHint: String

    func presetName(_ preset: NommoEQPreset) -> String {
        switch preset {
        case .game: return presetGame
        case .music: return presetMusic
        case .movie: return presetMovie
        case .flat: return presetFlat
        }
    }

    func lightingName(_ lighting: NommoLighting) -> String {
        switch lighting {
        case .off: return lightingOff
        case .spectrum: return lightingSpectrum
        case .solid: return lightingSolid
        }
    }

    func selectionName(_ selection: NommoEQSelection) -> String {
        switch selection {
        case let .builtIn(mode): return mode.razerName
        case let .preset(preset): return presetName(preset)
        case .otherCustom: return otherCustom
        case .unknown: return unknownMode
        }
    }
}

extension NommoBuiltInMode {
    /// Razer's own names, kept as Synapse shows them so the built-in modes are
    /// easy to tell from the presets of the same purpose.
    var razerName: String {
        switch self {
        case .game: return "Game"
        case .music: return "Music"
        case .movie: return "Movie"
        }
    }
}

extension FeatureStrings {
    static func nommo(_ language: AppLanguage) -> NommoFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension NommoFeatureStrings {
    static let enUS = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "Set the subwoofer, equalizer and standby of Razer Nommo V2 speakers over USB",
        panelDescription: "Subwoofer and equalizer for Razer Nommo V2 speakers",
        showInPanel: "Show Nommo V2 in the panel",
        notConnected: "Connect the speakers by USB and turn them on.",
        connected: "Connected",
        firmwareFormat: "Firmware %@",
        subwoofer: "Subwoofer",
        equalizer: "Equalizer",
        builtInGroup: "Razer built-in",
        builtInCaption: "Razer’s modes live in the speakers’ firmware, so their curves can’t be shown. Choosing one resets the custom bands on the speakers.",
        myEQGroup: "My EQ",
        presetGame: "Gaming",
        presetMusic: "Music",
        presetMovie: "Movies",
        presetFlat: "Flat",
        otherCustom: "Custom (other)",
        unknownMode: "Other mode",
        editCurve: "Edit my EQ",
        editCaption: "Dragging a band saves the curve on this Mac and plays it on the speakers. Levels run from −12 to +12; Razer doesn’t state the unit.",
        restoreSuggestion: "Restore suggestion",
        autoStandby: "Standby when idle",
        autoStandbyCaption: "After this long without sound, the speakers go to standby and disappear from this Mac. Press their power button to wake them.",
        standbyDelay: "Standby after",
        minutesFormat: "%d min",
        noReply: "The speakers didn’t answer. Check the USB cable and try again.",
        lighting: "Lighting",
        lightingOff: "Off",
        lightingSpectrum: "Spectrum",
        lightingCaption: "Kept on this Mac and put back after the speakers power on, and 3 seconds after a Razer built-in EQ mode shows its color.",
        lightingSolid: "Solid",
        lightingColor: "Color",
        brightness: "Brightness",
        addColor: "Add color…",
        deleteColor: "Delete Color",
        deleteHint: "Right-click to delete")

    static let ptBR = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "Ajuste o subwoofer, o equalizador e o modo de espera das caixas Razer Nommo V2 pelo USB",
        panelDescription: "Subwoofer e equalizador das caixas Razer Nommo V2",
        showInPanel: "Mostrar Nommo V2 no painel",
        notConnected: "Conecte as caixas pelo USB e ligue-as.",
        connected: "Conectadas",
        firmwareFormat: "Firmware %@",
        subwoofer: "Subwoofer",
        equalizer: "Equalizador",
        builtInGroup: "Integrados da Razer",
        builtInCaption: "Os modos da Razer ficam no firmware das caixas, por isso suas curvas não podem ser exibidas. Escolher um redefine as bandas personalizadas das caixas.",
        myEQGroup: "Meu EQ",
        presetGame: "Jogos",
        presetMusic: "Música",
        presetMovie: "Filmes",
        presetFlat: "Plano",
        otherCustom: "Personalizado (outro)",
        unknownMode: "Outro modo",
        editCurve: "Editar meu EQ",
        editCaption: "Ao arrastar uma banda, a curva é salva neste Mac e tocada nas caixas. Os níveis vão de −12 a +12; a Razer não informa a unidade.",
        restoreSuggestion: "Restaurar sugestão",
        autoStandby: "Espera quando ociosas",
        autoStandbyCaption: "Depois desse tempo sem som, as caixas entram em espera e somem deste Mac. Aperte o botão de energia delas para despertá-las.",
        standbyDelay: "Espera após",
        minutesFormat: "%d min",
        noReply: "As caixas não responderam. Verifique o cabo USB e tente de novo.",
        lighting: "Iluminação",
        lightingOff: "Desligada",
        lightingSpectrum: "Espectro",
        lightingCaption: "Fica guardada neste Mac e volta depois que as caixas ligam e 3 segundos após um modo de EQ integrado da Razer mostrar sua cor.",
        lightingSolid: "Cor única",
        lightingColor: "Cor",
        brightness: "Brilho",
        addColor: "Adicionar cor…",
        deleteColor: "Apagar cor",
        deleteHint: "Clique com o botão direito para apagar")

    static let tr = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "Razer Nommo V2 hoparlörlerin subwoofer, ekolayzer ve bekleme ayarlarını USB üzerinden yapın",
        panelDescription: "Razer Nommo V2 hoparlörler için subwoofer ve ekolayzer",
        showInPanel: "Nommo V2’yi panelde göster",
        notConnected: "Hoparlörleri USB ile bağlayıp açın.",
        connected: "Bağlı",
        firmwareFormat: "Donanım yazılımı %@",
        subwoofer: "Subwoofer",
        equalizer: "Ekolayzer",
        builtInGroup: "Razer yerleşik",
        builtInCaption: "Razer modları hoparlörlerin donanım yazılımında bulunur, bu yüzden eğrileri gösterilemez. Bir mod seçmek hoparlörlerdeki özel bantları sıfırlar.",
        myEQGroup: "EQ’m",
        presetGame: "Oyun",
        presetMusic: "Müzik",
        presetMovie: "Film",
        presetFlat: "Düz",
        otherCustom: "Özel (diğer)",
        unknownMode: "Diğer mod",
        editCurve: "EQ’mu düzenle",
        editCaption: "Bir bandı sürüklediğinizde eğri bu Mac’e kaydedilir ve hoparlörlerde çalınır. Seviyeler −12 ile +12 arasındadır; Razer birimi belirtmiyor.",
        restoreSuggestion: "Öneriyi geri yükle",
        autoStandby: "Boştayken beklemeye geç",
        autoStandbyCaption: "Bu süre boyunca ses olmazsa hoparlörler beklemeye geçer ve bu Mac’ten kaybolur. Uyandırmak için güç düğmesine basın.",
        standbyDelay: "Bekleme süresi",
        minutesFormat: "%d dk",
        noReply: "Hoparlörler yanıt vermiyor. USB kablosunu kontrol edip yeniden deneyin.",
        lighting: "Aydınlatma",
        lightingOff: "Kapalı",
        lightingSpectrum: "Spektrum",
        lightingCaption: "Bu Mac’te saklanır; hoparlörler açıldıktan sonra ve Razer yerleşik EQ modu rengini gösterdikten 3 saniye sonra geri yüklenir.",
        lightingSolid: "Tek renk",
        lightingColor: "Renk",
        brightness: "Parlaklık",
        addColor: "Renk ekle…",
        deleteColor: "Rengi sil",
        deleteHint: "Silmek için sağ tıklayın")

    static let ru = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "Настройка сабвуфера, эквалайзера и режима ожидания колонок Razer Nommo V2 по USB",
        panelDescription: "Сабвуфер и эквалайзер колонок Razer Nommo V2",
        showInPanel: "Показывать Nommo V2 на панели",
        notConnected: "Подключите колонки по USB и включите их.",
        connected: "Подключены",
        firmwareFormat: "Прошивка %@",
        subwoofer: "Сабвуфер",
        equalizer: "Эквалайзер",
        builtInGroup: "Встроенные Razer",
        builtInCaption: "Режимы Razer хранятся в прошивке колонок, поэтому их кривые нельзя показать. Выбор режима сбрасывает пользовательские полосы колонок.",
        myEQGroup: "Мой EQ",
        presetGame: "Игры",
        presetMusic: "Музыка",
        presetMovie: "Фильмы",
        presetFlat: "Ровный",
        otherCustom: "Свой (другой)",
        unknownMode: "Другой режим",
        editCurve: "Изменить мой EQ",
        editCaption: "При перетаскивании полосы кривая сохраняется на этом Mac и звучит в колонках. Уровни от −12 до +12; Razer не указывает единицы.",
        restoreSuggestion: "Вернуть рекомендацию",
        autoStandby: "Ожидание при простое",
        autoStandbyCaption: "Через это время без звука колонки переходят в режим ожидания и пропадают с этого Mac. Чтобы разбудить их, нажмите кнопку питания.",
        standbyDelay: "Ожидание через",
        minutesFormat: "%d мин",
        noReply: "Колонки не отвечают. Проверьте USB-кабель и повторите попытку.",
        lighting: "Подсветка",
        lightingOff: "Выкл.",
        lightingSpectrum: "Спектр",
        lightingCaption: "Хранится на этом Mac и восстанавливается после включения колонок и через 3 секунды после того, как встроенный режим EQ Razer покажет свой цвет.",
        lightingSolid: "Один цвет",
        lightingColor: "Цвет",
        brightness: "Яркость",
        addColor: "Добавить цвет…",
        deleteColor: "Удалить цвет",
        deleteHint: "Нажмите правой кнопкой, чтобы удалить")

    static let es = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "Ajusta el subwoofer, el ecualizador y el modo de espera de los altavoces Razer Nommo V2 por USB",
        panelDescription: "Subwoofer y ecualizador de los altavoces Razer Nommo V2",
        showInPanel: "Mostrar Nommo V2 en el panel",
        notConnected: "Conecta los altavoces por USB y enciéndelos.",
        connected: "Conectados",
        firmwareFormat: "Firmware %@",
        subwoofer: "Subwoofer",
        equalizer: "Ecualizador",
        builtInGroup: "Integrados de Razer",
        builtInCaption: "Los modos de Razer están en el firmware de los altavoces, así que sus curvas no se pueden mostrar. Elegir uno restablece las bandas personalizadas de los altavoces.",
        myEQGroup: "Mi EQ",
        presetGame: "Juegos",
        presetMusic: "Música",
        presetMovie: "Películas",
        presetFlat: "Plano",
        otherCustom: "Personalizado (otro)",
        unknownMode: "Otro modo",
        editCurve: "Editar mi EQ",
        editCaption: "Al arrastrar una banda, la curva se guarda en este Mac y suena en los altavoces. Los niveles van de −12 a +12; Razer no indica la unidad.",
        restoreSuggestion: "Restaurar sugerencia",
        autoStandby: "Espera en inactividad",
        autoStandbyCaption: "Tras este tiempo sin sonido, los altavoces entran en espera y desaparecen de este Mac. Pulsa su botón de encendido para activarlos.",
        standbyDelay: "Espera tras",
        minutesFormat: "%d min",
        noReply: "Los altavoces no responden. Revisa el cable USB e inténtalo de nuevo.",
        lighting: "Iluminación",
        lightingOff: "Apagada",
        lightingSpectrum: "Espectro",
        lightingCaption: "Se guarda en este Mac y se restaura al encender los altavoces y 3 segundos después de que un modo de EQ integrado de Razer muestre su color.",
        lightingSolid: "Color fijo",
        lightingColor: "Color",
        brightness: "Brillo",
        addColor: "Añadir color…",
        deleteColor: "Eliminar color",
        deleteHint: "Haz clic derecho para eliminarlo")

    static let sk = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "Nastavenie subwoofera, ekvalizéra a pohotovostného režimu reproduktorov Razer Nommo V2 cez USB",
        panelDescription: "Subwoofer a ekvalizér reproduktorov Razer Nommo V2",
        showInPanel: "Zobraziť Nommo V2 na paneli",
        notConnected: "Pripojte reproduktory cez USB a zapnite ich.",
        connected: "Pripojené",
        firmwareFormat: "Firmvér %@",
        subwoofer: "Subwoofer",
        equalizer: "Ekvalizér",
        builtInGroup: "Vstavané Razer",
        builtInCaption: "Režimy Razer sú vo firmvéri reproduktorov, preto ich krivky nemožno zobraziť. Výber režimu vynuluje vlastné pásma reproduktorov.",
        myEQGroup: "Môj EQ",
        presetGame: "Hry",
        presetMusic: "Hudba",
        presetMovie: "Filmy",
        presetFlat: "Rovný",
        otherCustom: "Vlastný (iný)",
        unknownMode: "Iný režim",
        editCurve: "Upraviť môj EQ",
        editCaption: "Pri ťahaní pásma sa krivka uloží do tohto Macu a zaznie z reproduktorov. Úrovne sú od −12 do +12; Razer neuvádza jednotku.",
        restoreSuggestion: "Obnoviť odporúčanie",
        autoStandby: "Pohotovosť pri nečinnosti",
        autoStandbyCaption: "Po tomto čase bez zvuku prejdú reproduktory do pohotovosti a zmiznú z tohto Macu. Zobudíte ich tlačidlom napájania.",
        standbyDelay: "Pohotovosť po",
        minutesFormat: "%d min",
        noReply: "Reproduktory neodpovedajú. Skontrolujte kábel USB a skúste to znova.",
        lighting: "Osvetlenie",
        lightingOff: "Vypnuté",
        lightingSpectrum: "Spektrum",
        lightingCaption: "Uloží sa v tomto Macu a obnoví sa po zapnutí reproduktorov a 3 sekundy po tom, čo vstavaný režim EQ Razer zobrazí svoju farbu.",
        lightingSolid: "Jedna farba",
        lightingColor: "Farba",
        brightness: "Jas",
        addColor: "Pridať farbu…",
        deleteColor: "Vymazať farbu",
        deleteHint: "Vymažete ju pravým kliknutím")

    static let de = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "Subwoofer, Equalizer und Standby von Razer-Nommo-V2-Lautsprechern über USB einstellen",
        panelDescription: "Subwoofer und Equalizer für Razer-Nommo-V2-Lautsprecher",
        showInPanel: "Nommo V2 im Panel anzeigen",
        notConnected: "Schließe die Lautsprecher per USB an und schalte sie ein.",
        connected: "Verbunden",
        firmwareFormat: "Firmware %@",
        subwoofer: "Subwoofer",
        equalizer: "Equalizer",
        builtInGroup: "Razer integriert",
        builtInCaption: "Razers Modi liegen in der Firmware der Lautsprecher, daher lassen sich ihre Kurven nicht anzeigen. Die Wahl eines Modus setzt die eigenen Bänder der Lautsprecher zurück.",
        myEQGroup: "Mein EQ",
        presetGame: "Spiele",
        presetMusic: "Musik",
        presetMovie: "Filme",
        presetFlat: "Neutral",
        otherCustom: "Eigene (andere)",
        unknownMode: "Anderer Modus",
        editCurve: "Meinen EQ bearbeiten",
        editCaption: "Beim Ziehen eines Bands wird die Kurve auf diesem Mac gesichert und auf den Lautsprechern abgespielt. Die Werte reichen von −12 bis +12; Razer nennt keine Einheit.",
        restoreSuggestion: "Vorschlag wiederherstellen",
        autoStandby: "Standby bei Stille",
        autoStandbyCaption: "Nach dieser Zeit ohne Ton gehen die Lautsprecher in den Standby und verschwinden von diesem Mac. Zum Aufwecken die Ein-/Aus-Taste drücken.",
        standbyDelay: "Standby nach",
        minutesFormat: "%d Min.",
        noReply: "Die Lautsprecher antworten nicht. Prüfe das USB-Kabel und versuche es erneut.",
        lighting: "Beleuchtung",
        lightingOff: "Aus",
        lightingSpectrum: "Spektrum",
        lightingCaption: "Wird auf diesem Mac gesichert und nach dem Einschalten der Lautsprecher sowie 3 Sekunden, nachdem ein integrierter Razer-EQ-Modus seine Farbe zeigt, wiederhergestellt.",
        lightingSolid: "Einfarbig",
        lightingColor: "Farbe",
        brightness: "Helligkeit",
        addColor: "Farbe hinzufügen …",
        deleteColor: "Farbe löschen",
        deleteHint: "Zum Löschen rechtsklicken")

    static let fr = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "Réglez le caisson de basses, l’égaliseur et la mise en veille des enceintes Razer Nommo V2 en USB",
        panelDescription: "Caisson de basses et égaliseur des enceintes Razer Nommo V2",
        showInPanel: "Afficher Nommo V2 dans le panneau",
        notConnected: "Branchez les enceintes en USB et allumez-les.",
        connected: "Connectées",
        firmwareFormat: "Firmware %@",
        subwoofer: "Caisson de basses",
        equalizer: "Égaliseur",
        builtInGroup: "Intégrés Razer",
        builtInCaption: "Les modes Razer sont dans le firmware des enceintes, leurs courbes ne peuvent donc pas être affichées. En choisir un réinitialise les bandes personnalisées des enceintes.",
        myEQGroup: "Mon EQ",
        presetGame: "Jeux",
        presetMusic: "Musique",
        presetMovie: "Films",
        presetFlat: "Plat",
        otherCustom: "Personnalisé (autre)",
        unknownMode: "Autre mode",
        editCurve: "Modifier mon EQ",
        editCaption: "Faire glisser une bande enregistre la courbe sur ce Mac et l’applique aux enceintes. Les niveaux vont de −12 à +12\u{00A0}; Razer n’en précise pas l’unité.",
        restoreSuggestion: "Rétablir la suggestion",
        autoStandby: "Veille en cas d’inactivité",
        autoStandbyCaption: "Après ce délai sans son, les enceintes se mettent en veille et disparaissent de ce Mac. Appuyez sur leur bouton d’alimentation pour les réveiller.",
        standbyDelay: "Veille après",
        minutesFormat: "%d min",
        noReply: "Les enceintes ne répondent pas. Vérifiez le câble USB et réessayez.",
        lighting: "Éclairage",
        lightingOff: "Éteint",
        lightingSpectrum: "Spectre",
        lightingCaption: "Conservé sur ce Mac et rétabli à l’allumage des enceintes, ainsi que 3 secondes après qu’un mode d’EQ intégré Razer affiche sa couleur.",
        lightingSolid: "Couleur unie",
        lightingColor: "Couleur",
        brightness: "Luminosité",
        addColor: "Ajouter une couleur…",
        deleteColor: "Supprimer la couleur",
        deleteHint: "Clic droit pour la supprimer")

    static let it = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "Regola subwoofer, equalizzatore e standby degli altoparlanti Razer Nommo V2 via USB",
        panelDescription: "Subwoofer ed equalizzatore degli altoparlanti Razer Nommo V2",
        showInPanel: "Mostra Nommo V2 nel pannello",
        notConnected: "Collega gli altoparlanti via USB e accendili.",
        connected: "Connessi",
        firmwareFormat: "Firmware %@",
        subwoofer: "Subwoofer",
        equalizer: "Equalizzatore",
        builtInGroup: "Integrati Razer",
        builtInCaption: "Le modalità Razer si trovano nel firmware degli altoparlanti, quindi le loro curve non si possono mostrare. Sceglierne una azzera le bande personalizzate degli altoparlanti.",
        myEQGroup: "Il mio EQ",
        presetGame: "Giochi",
        presetMusic: "Musica",
        presetMovie: "Film",
        presetFlat: "Piatto",
        otherCustom: "Personalizzato (altro)",
        unknownMode: "Altra modalità",
        editCurve: "Modifica il mio EQ",
        editCaption: "Trascinando una banda, la curva viene salvata su questo Mac e riprodotta dagli altoparlanti. I livelli vanno da −12 a +12; Razer non ne indica l’unità.",
        restoreSuggestion: "Ripristina suggerimento",
        autoStandby: "Standby se inattivi",
        autoStandbyCaption: "Dopo questo tempo senza suono, gli altoparlanti vanno in standby e scompaiono da questo Mac. Premi il loro tasto di accensione per riattivarli.",
        standbyDelay: "Standby dopo",
        minutesFormat: "%d min",
        noReply: "Gli altoparlanti non rispondono. Controlla il cavo USB e riprova.",
        lighting: "Illuminazione",
        lightingOff: "Spenta",
        lightingSpectrum: "Spettro",
        lightingCaption: "Salvata su questo Mac e ripristinata all’accensione degli altoparlanti e 3 secondi dopo che una modalità EQ integrata Razer mostra il suo colore.",
        lightingSolid: "Tinta unita",
        lightingColor: "Colore",
        brightness: "Luminosità",
        addColor: "Aggiungi colore…",
        deleteColor: "Elimina colore",
        deleteHint: "Fai clic destro per eliminarlo")

    static let ja = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "Razer Nommo V2 スピーカーのサブウーファー、イコライザー、自動スタンバイを USB で設定",
        panelDescription: "Razer Nommo V2 スピーカーのサブウーファーとイコライザー",
        showInPanel: "パネルに Nommo V2 を表示",
        notConnected: "スピーカーを USB で接続して電源を入れてください。",
        connected: "接続済み",
        firmwareFormat: "ファームウェア %@",
        subwoofer: "サブウーファー",
        equalizer: "イコライザー",
        builtInGroup: "Razer 内蔵",
        builtInCaption: "Razer のモードはスピーカーのファームウェアにあるため、カーブは表示できません。内蔵モードを選ぶと、スピーカーのカスタムバンドはリセットされます。",
        myEQGroup: "マイ EQ",
        presetGame: "ゲーム",
        presetMusic: "音楽",
        presetMovie: "映画",
        presetFlat: "フラット",
        otherCustom: "カスタム（その他）",
        unknownMode: "その他のモード",
        editCurve: "マイ EQ を編集",
        editCaption: "バンドをドラッグすると、カーブがこの Mac に保存されスピーカーで再生されます。レベルは −12〜+12 で、単位は Razer が公表していません。",
        restoreSuggestion: "推奨値に戻す",
        autoStandby: "無音時に自動スタンバイ",
        autoStandbyCaption: "この時間音が出ないとスピーカーはスタンバイになり、この Mac から消えます。復帰するにはスピーカーの電源ボタンを押してください。",
        standbyDelay: "スタンバイまで",
        minutesFormat: "%d 分",
        noReply: "スピーカーから応答がありません。USB ケーブルを確認してもう一度お試しください。",
        lighting: "ライティング",
        lightingOff: "オフ",
        lightingSpectrum: "スペクトラム",
        lightingCaption: "この Mac に保存され、スピーカーの電源投入後と、Razer 内蔵 EQ モードが色を表示してから 3 秒後に元に戻ります。",
        lightingSolid: "単色",
        lightingColor: "カラー",
        brightness: "明るさ",
        addColor: "カラーを追加…",
        deleteColor: "カラーを削除",
        deleteHint: "右クリックで削除")

    static let ko = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "USB로 Razer Nommo V2 스피커의 서브우퍼, 이퀄라이저, 자동 대기를 설정",
        panelDescription: "Razer Nommo V2 스피커의 서브우퍼와 이퀄라이저",
        showInPanel: "패널에 Nommo V2 표시",
        notConnected: "스피커를 USB로 연결하고 전원을 켜세요.",
        connected: "연결됨",
        firmwareFormat: "펌웨어 %@",
        subwoofer: "서브우퍼",
        equalizer: "이퀄라이저",
        builtInGroup: "Razer 내장",
        builtInCaption: "Razer 모드는 스피커 펌웨어에 있어 곡선을 표시할 수 없습니다. 내장 모드를 선택하면 스피커의 사용자 지정 밴드가 초기화됩니다.",
        myEQGroup: "내 EQ",
        presetGame: "게임",
        presetMusic: "음악",
        presetMovie: "영화",
        presetFlat: "플랫",
        otherCustom: "사용자 지정(기타)",
        unknownMode: "기타 모드",
        editCurve: "내 EQ 편집",
        editCaption: "밴드를 드래그하면 곡선이 이 Mac에 저장되고 스피커에서 재생됩니다. 레벨은 −12에서 +12까지이며, Razer는 단위를 밝히지 않았습니다.",
        restoreSuggestion: "권장값으로 복원",
        autoStandby: "유휴 시 자동 대기",
        autoStandbyCaption: "이 시간 동안 소리가 없으면 스피커가 대기 상태가 되고 이 Mac에서 사라집니다. 깨우려면 스피커의 전원 버튼을 누르세요.",
        standbyDelay: "대기 전 시간",
        minutesFormat: "%d분",
        noReply: "스피커가 응답하지 않습니다. USB 케이블을 확인하고 다시 시도하세요.",
        lighting: "조명",
        lightingOff: "끄기",
        lightingSpectrum: "스펙트럼",
        lightingCaption: "이 Mac에 저장되며, 스피커 전원을 켠 뒤와 Razer 내장 EQ 모드가 색을 표시한 지 3초 뒤에 복원됩니다.",
        lightingSolid: "단색",
        lightingColor: "색상",
        brightness: "밝기",
        addColor: "색상 추가…",
        deleteColor: "색상 삭제",
        deleteHint: "오른쪽 클릭으로 삭제")

    static let uk = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "Налаштування сабвуфера, еквалайзера й режиму очікування колонок Razer Nommo V2 через USB",
        panelDescription: "Сабвуфер і еквалайзер колонок Razer Nommo V2",
        showInPanel: "Показувати Nommo V2 на панелі",
        notConnected: "Під’єднайте колонки через USB і ввімкніть їх.",
        connected: "Під’єднано",
        firmwareFormat: "Прошивка %@",
        subwoofer: "Сабвуфер",
        equalizer: "Еквалайзер",
        builtInGroup: "Вбудовані Razer",
        builtInCaption: "Режими Razer зберігаються в прошивці колонок, тому їхні криві не можна показати. Вибір режиму скидає користувацькі смуги колонок.",
        myEQGroup: "Мій EQ",
        presetGame: "Ігри",
        presetMusic: "Музика",
        presetMovie: "Фільми",
        presetFlat: "Рівний",
        otherCustom: "Власний (інший)",
        unknownMode: "Інший режим",
        editCurve: "Змінити мій EQ",
        editCaption: "Під час перетягування смуги крива зберігається на цьому Mac і звучить у колонках. Рівні від −12 до +12; Razer не вказує одиниці.",
        restoreSuggestion: "Повернути рекомендацію",
        autoStandby: "Очікування під час простою",
        autoStandbyCaption: "Після цього часу без звуку колонки переходять у режим очікування й зникають із цього Mac. Щоб розбудити їх, натисніть кнопку живлення.",
        standbyDelay: "Очікування через",
        minutesFormat: "%d хв",
        noReply: "Колонки не відповідають. Перевірте USB-кабель і спробуйте ще раз.",
        lighting: "Підсвічування",
        lightingOff: "Вимк.",
        lightingSpectrum: "Спектр",
        lightingCaption: "Зберігається на цьому Mac і відновлюється після ввімкнення колонок та через 3 секунди після того, як вбудований режим EQ Razer покаже свій колір.",
        lightingSolid: "Один колір",
        lightingColor: "Колір",
        brightness: "Яскравість",
        addColor: "Додати колір…",
        deleteColor: "Видалити колір",
        deleteHint: "Клацніть правою кнопкою, щоб видалити")

    static let zhHans = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "通过 USB 调整 Razer Nommo V2 音箱的低音炮、均衡器和自动待机",
        panelDescription: "Razer Nommo V2 音箱的低音炮和均衡器",
        showInPanel: "在面板中显示 Nommo V2",
        notConnected: "请用 USB 连接音箱并打开电源。",
        connected: "已连接",
        firmwareFormat: "固件 %@",
        subwoofer: "低音炮",
        equalizer: "均衡器",
        builtInGroup: "Razer 内置",
        builtInCaption: "Razer 的模式存储在音箱固件中，无法显示曲线。选择内置模式会重置音箱上的自定义曲线。",
        myEQGroup: "我的 EQ",
        presetGame: "游戏",
        presetMusic: "音乐",
        presetMovie: "电影",
        presetFlat: "平直",
        otherCustom: "自定义（其他）",
        unknownMode: "其他模式",
        editCurve: "编辑我的 EQ",
        editCaption: "拖动任一频段时，曲线会保存在这台 Mac 上并在音箱上播放。数值范围为 −12 到 +12，Razer 没有说明单位。",
        restoreSuggestion: "恢复建议值",
        autoStandby: "闲置时自动待机",
        autoStandbyCaption: "没有声音超过这段时间后，音箱会进入待机并从这台 Mac 上消失，按音箱的电源键才能唤醒。",
        standbyDelay: "待机前等待",
        minutesFormat: "%d 分钟",
        noReply: "音箱没有响应，请检查 USB 线后重试。",
        lighting: "灯光",
        lightingOff: "关闭",
        lightingSpectrum: "彩虹循环",
        lightingCaption: "保存在这台 Mac 上；音箱开机后，以及切换 Razer 内置 EQ 显示该模式颜色 3 秒后，都会恢复为这里的设置。",
        lightingSolid: "单色",
        lightingColor: "颜色",
        brightness: "亮度",
        addColor: "添加颜色…",
        deleteColor: "删除颜色",
        deleteHint: "右键点按可删除")

    static let zhTW = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "透過 USB 調整 Razer Nommo V2 喇叭的重低音、等化器和自動待機",
        panelDescription: "Razer Nommo V2 喇叭的重低音和等化器",
        showInPanel: "在面板中顯示 Nommo V2",
        notConnected: "請用 USB 連接喇叭並開啟電源。",
        connected: "已連線",
        firmwareFormat: "韌體 %@",
        subwoofer: "重低音",
        equalizer: "等化器",
        builtInGroup: "Razer 內建",
        builtInCaption: "Razer 的模式存在喇叭的韌體裡，無法顯示曲線。選用內建模式時，喇叭上的自訂曲線會被重設。",
        myEQGroup: "我的 EQ",
        presetGame: "遊戲",
        presetMusic: "音樂",
        presetMovie: "電影",
        presetFlat: "平坦",
        otherCustom: "自訂（其他）",
        unknownMode: "其他模式",
        editCurve: "編輯我的 EQ",
        editCaption: "拖動任一頻段時，曲線會存在這台 Mac 上並在喇叭播放。數值範圍是 −12 到 +12，Razer 沒有說明單位。",
        restoreSuggestion: "還原建議值",
        autoStandby: "閒置時自動待機",
        autoStandbyCaption: "沒有聲音超過這段時間後，喇叭會進入待機並從這台 Mac 上消失，按喇叭的電源鍵才會喚醒。",
        standbyDelay: "待機前等待",
        minutesFormat: "%d 分鐘",
        noReply: "喇叭沒有回應，請檢查 USB 線後再試一次。",
        lighting: "燈光",
        lightingOff: "關閉",
        lightingSpectrum: "彩虹循環",
        lightingCaption: "存在這台 Mac 上；喇叭開機後，以及切換 Razer 內建 EQ 顯示該模式顏色 3 秒後，都會恢復成這裡的設定。",
        lightingSolid: "單色",
        lightingColor: "顏色",
        brightness: "亮度",
        addColor: "新增顏色…",
        deleteColor: "刪除顏色",
        deleteHint: "按右鍵可以刪除")

    static let zhHK = NommoFeatureStrings(
        title: "Razer Nommo V2",
        hubDescription: "透過 USB 調整 Razer Nommo V2 喇叭的重低音、均衡器和自動待機",
        panelDescription: "Razer Nommo V2 喇叭的重低音和均衡器",
        showInPanel: "在面板中顯示 Nommo V2",
        notConnected: "請用 USB 連接喇叭並開啟電源。",
        connected: "已連接",
        firmwareFormat: "固件 %@",
        subwoofer: "重低音",
        equalizer: "均衡器",
        builtInGroup: "Razer 內置",
        builtInCaption: "Razer 的模式儲存在喇叭的固件中，無法顯示曲線。選用內置模式時，喇叭上的自訂曲線會被重設。",
        myEQGroup: "我的 EQ",
        presetGame: "遊戲",
        presetMusic: "音樂",
        presetMovie: "電影",
        presetFlat: "平坦",
        otherCustom: "自訂（其他）",
        unknownMode: "其他模式",
        editCurve: "編輯我的 EQ",
        editCaption: "拖動任何頻段時，曲線會儲存在這部 Mac 並在喇叭播放。數值範圍為 −12 至 +12，Razer 沒有說明單位。",
        restoreSuggestion: "還原建議值",
        autoStandby: "閒置時自動待機",
        autoStandbyCaption: "沒有聲音超過這段時間後，喇叭會進入待機並從這部 Mac 消失，按喇叭的電源鍵才會喚醒。",
        standbyDelay: "待機前等待",
        minutesFormat: "%d 分鐘",
        noReply: "喇叭沒有回應，請檢查 USB 線後再試。",
        lighting: "燈光",
        lightingOff: "關閉",
        lightingSpectrum: "彩虹循環",
        lightingCaption: "儲存在這部 Mac；喇叭開機後，以及切換 Razer 內置 EQ 顯示該模式顏色 3 秒後，都會恢復為這裡的設定。",
        lightingSolid: "單色",
        lightingColor: "顏色",
        brightness: "亮度",
        addColor: "新增顏色…",
        deleteColor: "刪除顏色",
        deleteHint: "按右鍵可以刪除")
}
