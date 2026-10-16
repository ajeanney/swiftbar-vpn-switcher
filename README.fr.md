# Menu VPN SwiftBar

Pilotez vos VPN depuis la barre de menus de macOS : un clic pour se connecter, un clic pour se déconnecter, et le menu indique quel tunnel est actif. C'est du Bash pur au-dessus de [SwiftBar](https://swiftbar.app), sans étape de compilation.

Deux types de VPN sont pris en charge :

- **OpenVPN** (moteur `openvpn`) : n'importe quel profil `.ovpn`, lancé avec `sudo -n openvpn`. Vous pouvez définir
  plusieurs entrées pour le même serveur, par exemple un split tunnel et un tunnel complet.
- **F5 BIG-IP SSL VPN** (moteur `f5`) : le menu ouvre l'application officielle `F5 VPN.app` et l'URL de votre
  portail dans le navigateur. Vous vous connectez là-bas (mot de passe, MFA, ce que demande votre portail), et
  le portail passe la main au client F5. Le menu détecte quand le tunnel monte.

## Installation

1. Installez [SwiftBar](https://swiftbar.app), plus `brew install openvpn` et/ou le client F5 VPN.
2. Copiez `vpn.conf.example` en `vpn.conf` et listez vos VPN. `vpn.conf` est ignoré par git.
3. Pour chaque entrée OpenVPN, copiez `profiles/example-split.ovpn` ou `profiles/example-full.ovpn` et faites pointer sa
   ligne `config` vers le vrai profil fourni par votre administrateur. Gardez le vrai profil **en dehors** de ce dépôt,
   car il contient en général votre clé privée. Vos propres fichiers dans `profiles/` sont ignorés par git.
4. OpenVPN a besoin de root. Copiez `sudoers.example`, renseignez votre nom d'utilisateur, et installez-le avec
   `sudo visudo -f /etc/sudoers.d/vpn-menubar`. Il n'autorise que `openvpn` et `killall -TERM openvpn`.
5. Copiez `swiftbar-openconnect-wrapper.sh` dans votre dossier de plugins SwiftBar sous le nom `vpn.5s.sh` et modifiez le
   chemin à l'intérieur. Ce doit être un fichier normal, car SwiftBar ignore les liens symboliques. Le `5s` fixe l'intervalle
   de rafraîchissement, c'est ainsi que le menu détecte une connexion F5 terminée dans le navigateur.

## Ligne de commande

```bash
./vpn-manager.sh status            # connected / disconnected
./vpn-manager.sh profile           # id of the active VPN, or nothing
./vpn-manager.sh list              # configured VPNs
./vpn-manager.sh connect ID
./vpn-manager.sh disconnect
```

Les logs et l'état se trouvent dans `~/Library/Application Support/OpenConnectMenuBar/`. Utilisez "View VPN log" dans le
menu pour ouvrir celui du VPN actif.

## Limites

- Un seul VPN est actif à la fois. En connecter un déconnecte les autres.
- "Connected" signifie que le processus tourne et qu'une interface `utun` possède une adresse IPv4. Un autre VPN ou
  iCloud Private Relay peut aussi en créer une ; la correspondance des processus garde cela à peu près honnête.
- Un tunnel F5 démarré en dehors du menu est attribué à la première entrée `f5` de `vpn.conf`.
