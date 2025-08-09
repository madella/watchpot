# WatchPot - Caratteristiche di Resilienza

## Meccanismi di Resilienza Implementati

### 1. **Retry Logic negli Script**
- **capture_photo.py**: Retry automatico per cattura foto (max 3 tentativi con delay)
- **send_email.py**: Retry automatico per invio email (max 3 tentativi con delay)
- Gestione errori granulare per ogni operazione

### 2. **Logging Completo**
- Log dettagliati in `/var/log/watchpot/`
- Diversi livelli di log (INFO, WARNING, ERROR)
- Rotazione automatica dei log
- Log sia su file che console

### 3. **Gestione Errori Robusta**
- Try-catch per ogni operazione critica
- Fallback per operazioni non critiche
- Continuazione operazioni anche in caso di errori parziali

### 4. **Auto-recovery tramite Cron**
```bash
# Auto-restart capture se non in esecuzione (ogni 10 minuti)
*/10 * * * * pgrep -f capture_photo.py || /path/to/scripts/capture_photo.py --force
```

### 5. **Validazione Input e Configurazione**
- Controllo esistenza file di configurazione
- Validazione parametri prima dell'esecuzione
- Gestione valori di default per parametri mancanti

### 6. **Gestione Directory e Permessi**
- Creazione automatica directory se mancanti
- Controllo permessi di scrittura
- Pulizia automatica file vecchi

### 7. **Network Resilience**
- Timeout per connessioni HTTP/SMTP
- Retry per operazioni di rete
- Fallback per IP detection

### 8. **Email Sending Resilience**
- Gestione allegati con controllo dimensioni
- Fallback MIME type detection
- Validazione email prima dell'invio
- Gestione multiple recipients

### 9. **Photo Capture Resilience**
- Controllo spazio disco prima della cattura
- Validazione file foto dopo la cattura
- Pulizia automatica foto corrotte
- Gestione errori camera

### 10. **Scheduling Resilience**
- Finestra temporale per esecuzione (non timestamp esatto)
- Modalità --force per override schedule
- Gestione fuso orario

## Opzioni di Configurazione per Resilienza

```ini
# Retry settings
max_retries=3
retry_delay=30

# Cleanup settings  
cleanup_days=7
max_disk_usage=90

# Network timeouts
network_timeout=10
smtp_timeout=30

# Logging
log_level=INFO
log_retention_days=30
```

## Monitoring e Alerting

### Log Monitoring
```bash
# Vedere errori recenti
tail -f /var/log/watchpot/*.log | grep ERROR

# Contare errori oggi
grep "$(date +%Y-%m-%d)" /var/log/watchpot/*.log | grep ERROR | wc -l
```

### Sistema di Alert via Email
- Invio notifica se falliscono troppe foto consecutive
- Report giornaliero include stato sistema
- Notifica se spazio disco basso

## Recovery Procedures

### Manual Recovery
```bash
# Restart completo
./scripts/capture_photo.py --force
./scripts/send_email.py --force

# Cleanup forzato
./scripts/capture_photo.py --cleanup

# Test completo sistema
./test.sh
```

### Automatic Recovery
- Cron job ogni 10 minuti controlla processi
- Auto-restart se processo non trovato
- Pulizia automatica file corrotti

## Health Checks

Il sistema include health checks automatici:
- Controllo spazio disco
- Controllo temperature CPU
- Controllo connettività di rete
- Controllo stato servizi

Tutto questo rende WatchPot **estremamente resiliente** e capace di funzionare autonomamente anche durante problemi temporanei.
