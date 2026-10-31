// Section.qml — groupe vertical de modules.
// L'espace fait la séparation (brief §9) : aucun trait dessiné.
import QtQuick
import "."

Column {
    property int gap: Config.spacing

    spacing: gap
    width: Config.width - 16
}
