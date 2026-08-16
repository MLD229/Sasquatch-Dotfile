#!/bin/bash
# fix-suspend.sh — active le support suspend/resume propre pour NVIDIA
# (GTX 1660 Ti / driver 610). Sans ça : écran noir au réveil → reboot obligatoire.
#
# À lancer (sudo requis) :  sudo bash ~/.config/scripts/fix-suspend.sh
# (le repo est symlinké dans ~/.config, le script vit dans scripts/)
set -euo pipefail

GRUB=/etc/default/grub

echo "=== 1/3 — Paramètres kernel NVIDIA (GRUB) ==="
if grep -q "nvidia_drm.modeset=1" "$GRUB"; then
    echo "✔ déjà présents dans $GRUB"
else
    cp "$GRUB" "${GRUB}.bak.$(date +%Y%m%d-%H%M%S)"
    echo "→ backup: ${GRUB}.bak.*"
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia_drm.modeset=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"/' "$GRUB"
    echo "→ cmdline modifiée:"
    grep '^GRUB_CMDLINE_LINUX_DEFAULT' "$GRUB"
    grub-mkconfig -o /boot/grub/grub.cfg
    echo "✔ grub.cfg régénéré (REBOOT nécessaire pour activer modeset)"
fi

echo ""
echo "=== 2/3 — Services NVIDIA suspend/resume/hibernate ==="
systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service 2>&1
echo "✔ services activés"

echo ""
echo "=== 3/3 — Vérification ==="
echo "méthode de veille : $(cat /sys/power/mem_sleep)"
for s in nvidia-suspend nvidia-resume nvidia-hibernate; do
    echo "$s : $(systemctl is-enabled $s.service)"
done

echo ""
echo "=== Terminé ==="
echo "Un REBOOT est nécessaire (nvidia_drm.modeset)."
echo "Ensuite, test : systemctl suspend → réveiller → l'écran doit revenir sans reboot."
echo "Si l'écran ne revient toujours pas : hyprctl dispatch dpms on (hypridle le fait déjà via after_sleep_cmd)."
