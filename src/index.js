import { createClient } from '@supabase/supabase-js';

// Configuración de Supabase para la tabla "Applications"
// URL y clave proporcionadas por el usuario
const supabaseUrl = 'https://your-project.supabase.co';
const supabaseKey = 'YOUR_SUPABASE_ANON_KEY';

const supabase = createClient(supabaseUrl, supabaseKey);

// Función para cargar el archivo (mismo código existente)
async function uploadFile() {
  const fileInput = document.getElementById('fileInput');
  const progressBar = document.getElementById('progressBar');
  const file = fileInput.files[0];

  // Validaciones
  if (!file) {
    alert('Selecciona un archivo PDF para subir.');
    return;
  }

  if (file.type !== 'application/pdf') {
    alert('Solo se pueden subir archivos PDF.');
    return;
  }

  try {
    // Generar un nombre de archivo único
    const fileName = `cv_${Date.now()}_${file.name}`;

    // Subir el archivo con manejo de progreso mejorado
    const { data, error } = await supabase.storage
      .from('cvs')
      .upload(fileName, file, {
        cacheControl: '3600',
        upsert: false,
        onProgress: (event) => {
          const percentComplete = Math.round((event.loaded / event.total) * 100);
          progressBar.value = percentComplete;
        }
      });

    if (error) throw error;

    // Obtener URL pública del archivo
    const { data: urlData } = supabase.storage
      .from('cvs')
      .getPublicUrl(fileName);

    alert('Archivo subido correctamente');
    
    // Aquí podrías guardar la URL del archivo en tu base de datos
    // Por ejemplo, asociándolo a un usuario o registro específico
  }
}

// --- FUNCIONES DE APLICACIONES --------------------------------------------------

/**
 * Inserta un registro en la tabla "Applications".
 * @param {string} applicantEmail - Correo del solicitante
 * @param {string} website - Sitio donde se encontró la vacante
 * @param {string} vacancy - Nombre de la vacante
 * @param {string} status - Estado de la aplicación (ej. "pending", "accepted")
 * @param {string} applicationLink - Enlace a la aplicación o anuncio
 */
async function addApplication(applicantEmail, website, vacancy, status, applicationLink) {
  const { data, error } = await supabase
    .from('Applications')
    .insert([
      {
        applicant_email: applicantEmail,
        website,
        vaccancy: vacancy,
        status,
        application_link: applicationLink,
      },
    ]);

  if (error) {
    throw error;
  }
  return data;
}

/**
 * Obtiene todas las aplicaciones de un usuario dado su correo.
 * @param {string} applicantEmail
 */
async function getApplicationsByEmail(applicantEmail) {
  const { data, error } = await supabase
    .from('Applications')
    .select('*')
    .eq('applicant_email', applicantEmail);

  if (error) {
    throw error;
  }
  return data;
}

// ------------------------------------------------------------

  } catch (error) {
    alert(`Error: ${error.message}`);
    progressBar.value = 0;
  }
}

// Añadir event listener correcto
document.addEventListener('DOMContentLoaded', () => {
  const uploadButton = document.getElementById('uploadButton');
  const fileInput = document.getElementById('fileInput');

  uploadButton.addEventListener('click', uploadFile);
  
  // Opcional: Habilitar/deshabilitar botón según selección de archivo
  fileInput.addEventListener('change', () => {
    uploadButton.disabled = !fileInput.files.length;
  });

  // ------------------------------------------------------------
  // BUSQUEDA DE EMPLEO / CAPTURA DE APLICACIONES
  const searchButton = document.getElementById('searchButton');
  const searchInput = document.getElementById('searchInput');
  const jobsTableBody = document.querySelector('#jobsTable tbody');
  const emailInput = document.getElementById('emailInput');

  // simulación de búsqueda de vacantes (reemplazar por API real si es necesario)
  function searchJobs(query) {
    // datos estáticos de ejemplo
    const dummyJobs = [
      {
        vacancy: 'Desarrollador Front‑end',
        website: 'ejemplo.com',
        link: 'https://ejemplo.com/apply/123'
      },
      {
        vacancy: 'Ingeniero de Datos',
        website: 'otracompany.com',
        link: 'https://otracompany.com/apply/456'
      }
    ];

    // filtrar por query
    return dummyJobs.filter(j =>
      j.vacancy.toLowerCase().includes(query.toLowerCase()) ||
      j.website.toLowerCase().includes(query.toLowerCase())
    );
  }

  function renderJobs(jobs) {
    jobsTableBody.innerHTML = '';
    jobs.forEach(job => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${job.vacancy}</td>
        <td>${job.website}</td>
        <td><a href="${job.link}" target="_blank">Ir a oferta</a></td>
        <td><button class="apply-btn" data-vacancy="${job.vacancy}" data-website="${job.website}" data-link="${job.link}">Aplicar</button></td>
      `;
      jobsTableBody.appendChild(tr);
    });
  }

  searchButton.addEventListener('click', () => {
    const q = searchInput.value.trim();
    const results = searchJobs(q);
    renderJobs(results);
  });

  // delegado de eventos para los botones "Aplicar"
  jobsTableBody.addEventListener('click', async (event) => {
    if (event.target.matches('.apply-btn')) {
      const applicantEmail = emailInput.value.trim();
      if (!applicantEmail) {
        alert('Por favor ingresa tu correo antes de aplicar.');
        return;
      }

      const vacancy = event.target.dataset.vacancy;
      const website = event.target.dataset.website;
      const applicationLink = event.target.dataset.link;
      const status = 'pending';

      try {
        await addApplication(applicantEmail, website, vacancy, status, applicationLink);
        alert('Aplicación registrada correctamente.');
      } catch (err) {
        alert('Error al guardar la aplicación. Revisa la consola.');
      }
    }
  });
});