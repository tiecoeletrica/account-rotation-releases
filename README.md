# Account Rotation

Rodízio das contas do Claude Code da Ecoelétrica. Este repositório só distribui o app: as versões ficam nas
[Releases](https://github.com/tiecoeletrica/account-rotation-releases/releases), e os instaladores, aqui.

## Instalar

Uma vez só, sem precisar de administrador. O instalador baixa o Node e o app e, se faltar, instala o Google Chrome.
No fim, cria o atalho "Account Rotation" e abre o app.

**Windows** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/tiecoeletrica/account-rotation-releases/main/install.ps1 | iex
```

**Mac** (Terminal):

```bash
curl -fsSL https://raw.githubusercontent.com/tiecoeletrica/account-rotation-releases/main/install.sh | bash
```

Depois disso, é só abrir pelo atalho. O app se atualiza sozinho ao abrir, e fechar a janela fecha tudo.
Rodar o instalador de novo conserta a instalação sem apagar nada.
