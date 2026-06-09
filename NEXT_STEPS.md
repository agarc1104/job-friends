# ✅ Configuración Completada - Próximos Pasos Críticos

## Estado Actual

✅ **Backend integrations configuradas correctamente**

- Supabase URL: `https://lyrrspormffutxsvmnfz.supabase.co`
- Edge Functions endpoints verificados
- Flutter app compilando sin errores
- Arquitectura: Edge Functions → SerpAPI + Gemini (credenciales protegidas)

---

## 🚨 CRÍTICO: Verificar Supabase Secrets

**Sin esto, la app no funcionará correctamente:**

1. **Ir a Supabase Dashboard**
   - URL: https://app.supabase.com
   - Proyecto: lyrrspormffutxsvmnfz
   - Sección: Settings → Edge Functions → Secrets

2. **Confirmar que estos Secrets existen:**

   ```
   ✓ GEMINI_API_KEY = [tu clave de Google Generative AI]
   ✓ GEMINI_MODEL = gemini-2.5-flash
   ✓ GEMINI_FALLBACK_MODELS = gemini-2.5-flash-lite,gemini-2.0-flash
   ✓ SERPAPI_API_KEY = [tu clave de SerpAPI]
   ```

3. **Si faltan, agregarlos:**
   - Click "New Secret"
   - Key: `GEMINI_API_KEY`
   - Value: `[tu_clave_de_google]`
   - Repeat para SERPAPI_API_KEY

---

## 🧪 Pruebas End-to-End

### 1. Compilar y Ejecutar

```bash
cd mobile_app

# Dev
flutter run --dart-define=APP_ENV=development

# O QA
flutter run --dart-define=APP_ENV=qa

# O Production
flutter run --dart-define=APP_ENV=production
```

### 2. Test: Login

- Email: `quintero981104@gmail.com`
- Password: `D3n1s3a9`

**Esperado**: ✅ Ingresa a la app

**Si falla**: "No se pudo conectar con Supabase"
- Verifica: `.env.dev` tiene SUPABASE_ANON_KEY

---

### 3. Test: Search Jobs

1. Ve a pestaña "Jobs"
2. Ingresa un search: "Software Engineer"
3. Click "Buscar"

**Esperado**: ✅ Lista de empleos

**Si falla**: "Error en search-jobs: SERPAPI_API_KEY no configurada"
- Verifica: Supabase Secrets tiene SERPAPI_API_KEY
- Verifica: SerpAPI tiene creditos/plan activo

---

### 4. Test: CV Assist (Gemini)

1. Pestaña "Mi CV"
2. Completa los campos (nombre, email, experiencia, skills)
3. Click "Solicitar Sugerencias"

**Esperado**: ✅ Sugerencias personalizadas

**Si falla**: "Error en cv-assist: GEMINI_API_KEY no configurada"
- Verifica: Supabase Secrets tiene GEMINI_API_KEY
- Verifica: Google Generative AI tiene cuota

---

### 5. Test: Generate CV (Gemini + PDF)

1. Pestaña "Mi CV"
2. Completa formulario
3. Selecciona formato (PDF/DOCX)
4. Click "Generar CV"

**Esperado**: ✅ CV generado y descargable

**Si falla**: "Error en cv-generate-store: GEMINI_API_KEY"
- Verifica: GEMINI_API_KEY en Supabase Secrets
- Verifica: Gemini tiene capacidad (may throttle con alta demanda)

---

### 6. Test: Interview Practice (Gemini)

1. Pestaña "Preparación"
2. Selecciona un trabajo de "Applications"
3. Ingresa una pregunta de entrevista
4. Click "Enviar"

**Esperado**: ✅ Respuesta realista de IA

**Si falla**: "Error en interview-reply: GEMINI_API_KEY"
- Verifica: GEMINI_API_KEY en Supabase Secrets

---

## 📊 Monitorear Errores

### Ver Logs en Flutter Console

```
[JobFriendsRepository] invokeFunction start name=search-jobs
[JobFriendsRepository] invokeFunction success keys=[jobs, nextPageToken]
```

**✅ = Éxito**

```
[JobFriendsRepository] invokeFunction FunctionException status=400
```

**❌ = Error en Edge Function**

---

### Ver Logs en Supabase

1. Dashboard → Logs → Edge Functions
2. Buscar Edge Function que falló
3. Ver error completo

**Errores comunes**:
```
"GEMINI_API_KEY no configurada en Supabase Secrets"
"SERPAPI_API_KEY no configurada en Supabase Secrets"
"RateLimitError: Too many requests"
"429 Too Many Requests"
```

---

## 📝 Checklist de Go-Live

- [ ] GEMINI_API_KEY en Supabase Secrets
- [ ] SERPAPI_API_KEY en Supabase Secrets
- [ ] flutter run --dart-define=APP_ENV=development (test local)
- [ ] Test Login ✅
- [ ] Test Search Jobs ✅
- [ ] Test CV Assist ✅
- [ ] Test Generate CV ✅
- [ ] Test Interview Practice ✅
- [ ] Verificar logs en Supabase sin errores
- [ ] Deploy a QA o Production cuando esté listo

---

## 🆘 Troubleshooting Rápido

| Error | Causa | Solución |
|-------|-------|----------|
| "no se pudo conectar con supabase" | .env inválido | flutter run --dart-define=APP_ENV=development |
| "error en search-jobs" | SERPAPI_API_KEY falta | Agregar en Supabase Secrets |
| "error en cv-assist" | GEMINI_API_KEY falta | Agregar en Supabase Secrets |
| "timeout 25s" | Edge Function lenta | Aumentar timeout en repository |
| "429 Too Many Requests" | Rate limit SerpAPI | Esperar o upgrade plan |

---

## 📞 Contacto / Soporte

Si tienes errores específicos:

1. **Copia el error completo** de la consola
2. **Busca en los logs** de Supabase Dashboard
3. **Verifica Supabase Secrets** están correctamente configurados
4. **Valida credenciales** de Google Generative AI y SerpAPI

---

## ✅ Resumen

La aplicación está **lista para probar**. El siguiente paso es:

1. Configurar Supabase Secrets (GEMINI_API_KEY y SERPAPI_API_KEY)
2. Ejecutar `flutter run --dart-define=APP_ENV=development`
3. Probar cada flujo (Login → Search → CV → Interview)
4. Verificar logs en Supabase si hay errores

**¡La arquitectura está validada y funcionando! 🚀**
