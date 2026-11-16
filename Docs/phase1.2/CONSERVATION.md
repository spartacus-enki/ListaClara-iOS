# Conservación del trabajo existente

## Integridad y copias

Archivo original: `/tmp/ListaClara-iOS-1.0.0.tar.gz`.

SHA-256 verificado: `fa20b9aca4e68a2ebf680cf35f67f3bd3140490ee55997bde47819df31590493`.

Se verificaron las 32 entradas del manifiesto del archivo original antes de editar. Se extrajo una copia independiente en `/tmp/ListaClara-iOS-fase1.2/project`. El archivo y la carpeta originales permanecen intactos. Git conserva ese contenido en el commit inicial y la preparación de Codemagic en commits posteriores. El manifiesto original quedó en `Docs/phase1.2/original-1.0.0-MANIFEST.sha256`; el manifiesto raíz nuevo corresponde a la entrega actual.

La entrega incluye un bundle Git independiente con todo el historial y una nueva copia del archivo fuente original en `backups/`, cada uno con SHA-256. No se configuró un remoto externo, ni se creó un repositorio en un proveedor, ni se subió contenido. El repositorio de trabajo se encuentra bajo una carpeta de acceso local restringido.

## Bloqueo de ruta y comando del propietario

La sesión solo permite escribir en Android y `/tmp`. Como Android debe permanecer intacto, no se intentó escribir fuera del sandbox ni pedir elevación. **La carpeta permanente todavía no está creada por el agente.** El propietario puede ejecutar desde su terminal normal:

```sh
bash /tmp/ListaClara-iOS-fase1.2/conservar.sh
```

El wrapper comprueba los checksums y llama a `Tools/conserve_project.py`. Este instalador:

1. Se niega a escribir dentro de Android, en un ancestro de Android o sobre una carpeta ya existente.
2. Verifica el archivo original y el bundle Git.
3. Copia el original y el bundle a una subcarpeta con fecha en `/home/dexanox/Servicios/TaskFamily/ListaClara-iOS-backups` y comprueba sus hashes.
4. Clona localmente el historial en `/home/dexanox/Servicios/TaskFamily/ListaClara-iOS`, elimina el remoto local de importación, restringe el directorio a su propietario y ejecuta `git fsck` y validación estructural.

No necesita sudo si el padre pertenece al propietario y es escribible desde su terminal. Si existe ya un checkout iOS, el script se detiene para revisión; no lo sobrescribe. Si falta permiso normal sobre el directorio padre, elegir primero una ubicación persistente propia, con `bash conservar.sh /ruta/propia/ListaClara-iOS`, en vez de cambiar permisos del sistema o de Android.

Comprobación después de conservar:

```sh
cd /home/dexanox/Servicios/TaskFamily/ListaClara-iOS
git status --short
git log --oneline -3
git remote -v
sha256sum -c MANIFEST.sha256
python3 Tools/validate_delivery.py
```

El remoto debe estar vacío hasta la autorización externa. No borrar `/tmp` hasta comprobar el checkout y las copias permanentes. Los archivos temporales no sustituyen una copia permanente.

## Reversión

La preparación solo cambia iOS y añade herramientas CI/documentación. Puede restaurarse el commit fuente inicial desde Git o el archivo original en una ubicación independiente, sin tocar Android ni el backend. No hay servicios ni bases productivas que revertir. Antes de futuros cambios iOS, conservar su estado/commit; no usar desinstalación de la app como mecanismo de rollback de datos.
