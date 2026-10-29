'use strict';
const search=document.getElementById('format-search');
if(search){const rows=[...document.querySelectorAll('#format-table tbody tr')];search.addEventListener('input',()=>{const term=search.value.trim().toLowerCase();for(const row of rows)row.hidden=!row.textContent.toLowerCase().includes(term);});}
