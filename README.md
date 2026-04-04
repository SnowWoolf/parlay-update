### 1. Установить Python 3.10
```
curl -fsSL https://raw.githubusercontent.com/SnowWoolf/parlay-update/main/install_py3.10.sh | bash
```

### 2. Установить / обновить Parlay
```
curl -fsSL https://raw.githubusercontent.com/SnowWoolf/parlay-update/main/install_parlay.sh | bash
```
### 3. Развернуть базу данных:
   
- Восстановить бэкап с Windows

На Windows:
```
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -h 192.168.0.1 -U parlay -d parlay -f base.sql
```

- Ограничить доступ к PostgreSQL только localhost 
```
curl -fsSL https://raw.githubusercontent.com/SnowWoolf/parlay-update/main/lock_postgres_localonly.sh | bash
```
