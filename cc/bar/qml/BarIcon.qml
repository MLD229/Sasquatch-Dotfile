// BarIcon.qml — glyphe Nerd Font centré SUR SA CASE (brief v3 §5).
//
// PROBLÈME MESURÉ (v2) : un glyphe Nerd Font n'a pas les métriques d'un
// caractère de texte. Dans JetBrainsMono Nerd Font, l'AVANCE d'un glyphe vaut
// 0,6 em (9,59 px à 16 px) alors que son ENCRE peut faire 19 px de large
// (wifi U+F1EB, son U+F028). Un `Text` centré par `anchors.centerIn` centre
// l'avance, pas l'encre : wifi/son/DND partaient de 4,7 px vers la droite dans
// une case de 38 px. Les chiffres et les lettres, eux, sont déjà centrés
// (écart ≤ 0,25 px) : la table ci-dessous ne contient donc que les glyphes.
//
// MÉTHODE (reproductible, hors ligne) :
//   font = JetBrainsMonoNerdFont-Regular.ttf, taille 16 px
//   advance = font.getlength(ch)                 ;  ascent/descent = getmetrics()
//   bbox    = font.getbbox(ch, anchor="ls")      ;  encre = (x0,y0)-(x1,y1)
//   dx = advance/2 − (x0 + x1)/2                 (décalage horizontal de l'encre)
//   dy = (ascent+descent)/2 − (ascent + (y0+y1)/2)  (décalage vertical)
// Les valeurs sont pour 16 px et remises à l'échelle (× size/16) : la
// compensation suit donc appearance.iconSize de bar.json.
//
// Le glyphe est un `Text` dont la case est le PARENT (38 px) : alignements
// imposés (AlignHCenter/AlignVCenter) + décalage d'encre explicite. Aucune
// couleur en dur, aucune taille en dur.
import QtQuick
import "."

Item {
    id: icon

    property color tint: BarPalette.text
    property int size: 16
    property string text: ""
    property bool inkCentered: true

    // glyphe → [dx, dy] à 16 px (voir la méthode ci-dessus).
    readonly property var inkTable: ({
        "\uf002": [-2.70,  0.00],   // loupe
        "\uf013": [-2.20,  0.00],   // engrenage
        "\uf073": [-1.70,  0.00],   // calendrier
        "\uf026": [-0.20,  0.00],   // son muet
        "\uf028": [-4.70,  0.00],   // son
        "\uf1eb": [-4.70,  0.00],   // wifi
        "\uf071": [-2.20,  0.00],   // alerte / indisponible
        "\uf1f6": [-4.20,  0.00],   // ne pas déranger (actif)
        "\uf0f3": [-1.70,  0.00],   // cloche
        "\uf00d": [-0.20, -0.50],   // croix (fermer)
        "\uf060": [-1.70,  0.00],   // chevron précédent
        "\uf061": [-1.70,  0.00],   // chevron suivant
        "\uf1f8": [-1.70,  0.00],   // corbeille
        "\uf0eb": [-0.70,  0.00],   // luminosité
        "\uf2d0": [-2.70,  0.00],   // fenêtres (menu d'app)  
        "\u002b": [-0.20, -1.50],   // « + » (épingler)
        "\u00b7": [-0.20, -2.50]    // point médian (état vide)
    })

    readonly property var ink: icon.inkTable[icon.text] !== undefined
                               ? icon.inkTable[icon.text] : [0, 0]
    property real inkDx: icon.inkCentered ? icon.ink[0] * icon.size / 16 : 0
    property real inkDy: icon.inkCentered ? icon.ink[1] * icon.size / 16 : 0

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    Text {
        id: label
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: icon.inkDx
        anchors.verticalCenterOffset: icon.inkDy
        text: icon.text
        color: icon.tint
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: icon.size
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
        Behavior on color { ColorAnimation { duration: 120 } }
    }
}
