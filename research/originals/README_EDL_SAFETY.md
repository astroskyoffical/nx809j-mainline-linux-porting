# Guia de Segurança para Gravação de ROMs via EDL 9008 (Redmagic)

Este guia explica como preparar e modificar ROMs de outros modelos (ex: ROM do Redmagic 11S instalada no Redmagic 11 Pro+ NX809J) de forma segura no futuro, evitando falhas de inicialização (Hard Bricks) ou perda definitiva de rede/IMEI.

---

## 1. O Risco das Partições Críticas (NV/Calibração)

Ao realizar o backup total (readback) de um aparelho para criar uma ROM 9008, a ferramenta lê **todas** as partições físicas. Algumas dessas partições contêm chaves de hardware, calibrações de antenas e IDs exclusivos que são **únicos de cada celular**.

> [!WARNING]
> Nunca grave partições exclusivas de calibração obtidas de outro aparelho. Isso pode causar a perda do sinal de rede (IMEI zerado) ou impedir o bootloader de validar a placa, gerando um **Hard Brick**.

### Partições que devem ser PROTEGIDAS (Ignoradas no Flash)

| Partição | Função Crítica | O que acontece se sobrescrever? |
| :--- | :--- | :--- |
| `modemst1` / `modemst2` | Calibração de rádio (EFS/RF) e IMEI do celular. | Perda permanente de sinal de operadora e IMEI zerado. |
| `fsg` / `fsc` / `fs_bkup` | Segurança e integridade do sistema de arquivos do modem. | Celular fica sem rede ou em loop de modem. |
| `persist` | Calibração de sensores (giroscópio, proximidade), chaves DRM e biometria. | Sensores param de funcionar e o leitor de digital falha. |
| `devinfo` | Informações exclusivas do aparelho (serial, ID da placa, estado do bootloader). | Falha na verificação de assinatura de segurança (Hard Brick). |
| `ztecfg` | Arquivos de configuração de modelo e projeto da ZTE/Redmagic. | Incompatibilidade de modelo que impede o início do sistema. |
| `ssd` / `frp` / `keystore` | Chaves de criptografia e proteção de conta. | Loops de criptografia ou bloqueios de tela. |

---

## 2. Como Preparar uma Nova ROM com Segurança (Passo a Passo)

Sempre que obtiver uma nova ROM baseada em backup EDL (9008) de outro dispositivo, siga este protocolo antes de conectar o aparelho ao computador:

### Passo 1: Limpar as Partições Protegidas nos XMLs
Abra todos os arquivos de mapeamento da ROM (geralmente chamados de `rawprogram0.xml` até `rawprogram5.xml`) em um editor de texto e localize as partições protegidas citadas na tabela acima.

Altere o atributo `filename` para **vazio** (`""`). 
* **Incorreto (Perigoso):** `<program filename="modemst1.img" label="modemst1" ... />`
* **Correto (Seguro):** `<program filename="" label="modemst1" ... />`

*Isso instrui a ferramenta EDL a pular a gravação dessas partições, mantendo os arquivos originais e seguros do seu próprio aparelho.*

### Passo 2: Garantir a Presença dos Arquivos de Patch (`patch*.xml`)
A ferramenta de gravação EDL exige arquivos de patch (`patch0.xml` a `patch5.xml`) correspondentes para poder calcular o tamanho dinâmico do armazenamento (especialmente a partição `userdata`).
* Se a nova ROM não possuir arquivos `patch*.xml`, use a ferramenta `ptool.py` (ou `ptool.exe`) para gerá-los a partir do `partition.xml` do backup.
* **Dica:** Se o layout de setores da nova ROM for idêntico ao da ROM atual (mesmo tamanho e setores iniciais das partições), você pode copiar os arquivos `patch*.xml` de uma ROM conhecida que funcione.

### Passo 3: Unificar os Slots A e B (Recomendável)
ROMs de backup costumam ler as partições duplicadas dos slots A e B (`abl_a.img`, `abl_b.img`). Para economizar espaço e evitar erros de slots alternados:
1. Delete todos os arquivos com final `_b.img` na pasta de imagens.
2. Renomeie os arquivos com final `_a.img` removendo o sufixo `_a` (ex: `boot_a.img` $\rightarrow$ `boot.img`).
3. No arquivo `rawprogram*.xml`, configure o instalador para gravar o mesmo arquivo genérico nos dois slots:
   * `<program filename="boot.img" label="boot_a" ... />`
   * `<program filename="boot.img" label="boot_b" ... />`

---

## 3. Checklist de Pré-Flash (Regra de Ouro)

Antes de iniciar qualquer gravação via EDL 9008, faça esta verificação final:

- [ ] **Backup:** Você possui um backup EDL completo (`modemst1`, `modemst2`, `persist`, `ztecfg`, `devinfo`) do **seu próprio aparelho** salvo em um local seguro? (Se não tiver, faça a leitura dele antes de qualquer flash).
- [ ] **XMLs de Gravação:** Verificou os arquivos `rawprogram*.xml` da ROM que vai instalar e confirmou que os campos `filename` de `modemst1`, `modemst2`, `persist`, `ztecfg` e `devinfo` estão **vazios** (`filename=""`)?
- [ ] **Patches:** Os arquivos `patch0.xml` a `patch5.xml` estão presentes na pasta de instalação junto com os XMLs principais?
