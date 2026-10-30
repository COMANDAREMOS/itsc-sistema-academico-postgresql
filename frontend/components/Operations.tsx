'use client';

import { useEffect, useState } from 'react';
import { api, params } from '../lib/api';
import { DataTable, Empty, Filters, Loading, message, Module, Notice, NoticeFn, Pagination, QuerySelect, Row, User } from './ui';

export function GroupEnrollment({ filters, notify }: { filters: Filters; notify: NoticeFn }) {
  const [group, setGroup] = useState(filters.grupo_id), [search, setSearch] = useState(''), [query, setQuery] = useState(''), [page, setPage] = useState(1), [revision, setRevision] = useState(0);
  const [selected, setSelected] = useState<Set<string>>(new Set()), [data, setData] = useState<Row | null>(null), [loading, setLoading] = useState(false), [error, setError] = useState(''), [saving, setSaving] = useState(false);
  useEffect(() => { setGroup(filters.grupo_id); }, [filters.grupo_id, filters.periodo_id, filters.carrera_id]);
  useEffect(() => { setSelected(new Set()); setPage(1); setQuery(''); setSearch(''); }, [group]);
  useEffect(() => {
    if (!group) { setData(null); return; }
    let active = true; setLoading(true); setError('');
    api(`/grupos/${group}/candidatos?${params({ q: query, page })}`).then(result => { if (active) setData(result); }).catch(err => { if (active) { setError(message(err)); setData(null); } }).finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [group, query, page, revision]);
  const rows: Row[] = data?.rows || [];
  function select(id: string, checked: boolean) { setSelected(previous => { const next = new Set(previous); if (checked) { if (next.size >= 100) { notify('Puedes seleccionar hasta 100 matrículas por operación.', true); return previous; } next.add(id); } else next.delete(id); return next; }); }
  async function save() {
    setSaving(true);
    try { const result = await api(`/grupos/${group}/inscribir`, { method: 'POST', body: JSON.stringify({ matricula_ids: Array.from(selected).map(Number) }) }); notify(result.message || 'Inscripciones del grupo guardadas correctamente.'); setSelected(new Set()); setRevision(value => value + 1); } catch (err) { notify(message(err), true); } finally { setSaving(false); }
  }
  return <><section className="panel"><div className="panel-heading"><div><span className="eyebrow muted">ORGANIZACIÓN POR GESTIÓN</span><h2>Inscripción por grupo</h2></div><span className="pill">Hasta 100 matrículas</span></div><div className="operation-selector"><QuerySelect label="Grupo de destino" source="grupos" value={group} onChange={setGroup} filters={{ periodo_id: filters.periodo_id, carrera_id: filters.carrera_id }} /></div><p className="subtle operation-help">Selecciona las matrículas activas de la misma carrera y gestión. El proceso asigna el grupo e inscribe sus materias, respetando cupos y requisitos.</p>{data?.grupo && <div className="selection-summary"><strong>{data.grupo.nombre || data.grupo.label || `${data.grupo.curso || ''}° ${data.grupo.paralelo || ''} · ${data.grupo.turno || ''}`}</strong><span>{data.ofertas?.length ?? 0} ofertas de materias vinculadas</span></div>}</section>
    <section className="panel records-panel"><div className="panel-heading"><div><span className="eyebrow muted">MATRÍCULAS DISPONIBLES</span><h2>Estudiantes del grupo<span className="count">{data?.total ?? 0}</span></h2></div></div>{!group ? <Empty text="Selecciona un grupo para consultar sus matrículas." /> : <><form className="search records-search" onSubmit={event => { event.preventDefault(); setQuery(search); setPage(1); }}><input type="search" aria-label="Buscar matrícula o estudiante" placeholder="Registro o nombre del estudiante" value={search} onChange={event => setSearch(event.target.value)} /><button className="text-button">Buscar</button></form>{error ? <div className="table-error"><Notice text={error} error /><button className="button secondary" onClick={() => setRevision(value => value + 1)}>Volver a intentar</button></div> : loading ? <Loading /> : <><div className="bulk-tools"><button className="text-button" type="button" disabled={!rows.length || saving} onClick={() => setSelected(previous => new Set([...previous, ...rows.map(row => String(row.matricula_id ?? row.id))].slice(0, 100)))}>Seleccionar esta página</button><button className="text-button" type="button" disabled={!selected.size || saving} onClick={() => setSelected(new Set())}>Limpiar selección</button><strong>{selected.size} seleccionadas</strong></div><DataTable rows={rows} columns={[{ key: 'registro', label: 'Registro' }, { key: 'estudiante', label: 'Estudiante' }, { key: 'asignado', label: 'Ya pertenece al grupo' }]} selectable={row => String(row.matricula_id ?? row.id)} selected={selected} onSelect={select} /><Pagination page={data?.page || page} total={data?.total || 0} pageSize={data?.pageSize || 50} onPage={setPage} /><div className="operation-footer"><span className="subtle">Se comprueban todas las matrículas antes de guardar.</span><button className="button" type="button" disabled={!selected.size || saving || !data?.ofertas?.length} onClick={save}>{saving ? 'Procesando…' : `Inscribir ${selected.size || ''} matrículas →`}</button></div></>}</>}
    </section></>;
}

export function Roster({ type, filters, notify }: { type: 'notas' | 'asistencias'; filters: Filters; notify: NoticeFn }) {
  const [offer, setOffer] = useState(''), [target, setTarget] = useState(''), [data, setData] = useState<Row | null>(null), [values, setValues] = useState<Record<string, string>>({}), [loading, setLoading] = useState(false), [error, setError] = useState(''), [saving, setSaving] = useState(false), [revision, setRevision] = useState(0);
  const targetKey = type === 'notas' ? 'evaluacion_id' : 'sesion_id';
  const filterKey = params(filters);
  useEffect(() => { setOffer(''); setTarget(''); setData(null); setValues({}); }, [filterKey, type]);
  useEffect(() => { setTarget(''); setValues({}); }, [offer]);
  useEffect(() => {
    if (!offer) { setData(null); return; }
    let active = true; setLoading(true); setError('');
    api(`/planillas?${params({ tipo: type, oferta_id: offer, [targetKey]: target })}`).then(result => { if (active) { setData(result); setValues(Object.fromEntries((result.rows || []).map((row: Row) => [String(row.inscripcion_id), row.valor == null ? '' : String(row.valor)]))); } }).catch(err => { if (active) { setError(message(err)); setData(null); } }).finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [offer, target, type, revision]);
  const rows: Row[] = data?.rows || [];
  const editable = data?.editable !== false;
  async function save(event: React.FormEvent) {
    event.preventDefault(); setSaving(true);
    const registros = rows.filter(row => values[String(row.inscripcion_id)] !== '' && values[String(row.inscripcion_id)] != null).map(row => ({ inscripcion_id: row.inscripcion_id, valor: Number(values[String(row.inscripcion_id)]) }));
    try { const result = await api('/planillas', { method: 'POST', body: JSON.stringify({ tipo: type, oferta_id: Number(offer), [targetKey]: Number(target), registros }) }); notify(result.message || 'Planilla guardada correctamente.'); setRevision(value => value + 1); } catch (err) { notify(message(err), true); } finally { setSaving(false); }
  }
  return <><section className="panel"><div className="panel-heading"><div><span className="eyebrow muted">EVALUACIÓN Y SEGUIMIENTO</span><h2>{type === 'notas' ? 'Planilla de calificaciones' : 'Planilla de asistencia'}</h2></div></div><div className="form-grid"><QuerySelect label="Oferta de materia" source="ofertas" value={offer} onChange={setOffer} filters={filters} />{offer && <QuerySelect label={type === 'notas' ? 'Evaluación' : 'Sesión realizada'} source={type === 'notas' ? 'evaluaciones' : 'sesiones'} value={target} onChange={setTarget} filters={{ oferta_id: offer }} />}</div><p className="subtle operation-help">{type === 'notas' ? 'Registra notas de 1 a 100. Los espacios en blanco conservan los valores existentes.' : 'Registra los minutos de asistencia. Usa 0 para una falta; los espacios en blanco conservan los valores existentes.'}</p></section>
    <section className="panel records-panel"><div className="panel-heading"><div><span className="eyebrow muted">ESTUDIANTES INSCRITOS</span><h2>{type === 'notas' ? 'Calificaciones' : 'Minutos de asistencia'}<span className="count">{rows.length}</span></h2></div>{data && !editable && <span className="status-badge status-cerrado">Oferta cerrada</span>}</div>{error ? <div className="table-error"><Notice text={error} error /><button className="button secondary" onClick={() => setRevision(value => value + 1)}>Volver a intentar</button></div> : loading ? <Loading /> : !offer || !target ? <Empty text={`Selecciona una oferta y ${type === 'notas' ? 'una evaluación' : 'una sesión'} para abrir la planilla.`} /> : !rows.length ? <Empty text="Esta oferta todavía no tiene estudiantes inscritos." /> : <form onSubmit={save}><div className="table-wrap"><table><caption className="sr-only">Planilla de {type === 'notas' ? 'notas' : 'asistencia'}</caption><thead><tr><th scope="col">Registro</th><th scope="col">Estudiante</th><th scope="col">{type === 'notas' ? 'Nota (1 a 100)' : `Minutos (0 a ${data?.max ?? 'duración'})`}</th></tr></thead><tbody>{rows.map(row => <tr key={row.inscripcion_id}><td>{row.registro}</td><td>{row.estudiante}</td><td><input className="roster-input" type="number" min={data?.min ?? (type === 'notas' ? 1 : 0)} max={data?.max ?? (type === 'notas' ? 100 : undefined)} step={type === 'notas' ? '0.01' : '1'} value={values[String(row.inscripcion_id)] ?? ''} onChange={event => setValues(previous => ({ ...previous, [String(row.inscripcion_id)]: event.target.value }))} aria-label={`${type === 'notas' ? 'Nota' : 'Minutos de asistencia'} de ${row.estudiante}`} disabled={!editable || saving} /></td></tr>)}</tbody></table></div><div className="operation-footer"><span className="subtle">{editable ? 'La planilla se valida y guarda en una sola operación.' : 'Consulta disponible. La oferta cerrada no admite modificaciones.'}</span>{editable && <button className="button" type="submit" disabled={saving}>{saving ? 'Guardando…' : 'Guardar planilla →'}</button>}</div></form>}</section></>;
}

const reportTypes = [
  { value: 'matriculas', label: 'Matrículas por gestión' },
  { value: 'notas', label: 'Calificaciones' },
  { value: 'asistencias', label: 'Asistencia por sesión' },
  { value: 'boletin', label: 'Boletín de resultados' },
  { value: 'saldos', label: 'Saldos y pagos' },
  { value: 'grupos', label: 'Grupos por gestión' },
  { value: 'horarios', label: 'Horarios y aulas' },
  { value: 'estudiantes', label: 'Registro de estudiantes' },
  { value: 'docentes', label: 'Registro de docentes' },
];

export function Reports({ filters, modules, notify }: { filters: Filters; modules: Module[]; notify: NoticeFn }) {
  const allowed = reportTypes.filter(report => modules.some(module => module.key === report.value));
  const [type, setType] = useState(allowed[0]?.value || 'saldos'), [downloading, setDownloading] = useState('');
  async function download(format: 'pdf' | 'xlsx') {
    setDownloading(format);
    try {
      const response = await fetch(`/api/reportes?${params({ ...filters, tipo: type, formato: format })}`, { credentials: 'same-origin', cache: 'no-store' });
      if (!response.ok) {
        if (response.status === 401) window.dispatchEvent(new Event('itsc-session-expired'));
        let detail: any; try { detail = await response.json(); } catch { detail = {}; }
        throw new Error(detail.message || 'No se pudo generar el reporte.');
      }
      const blob = await response.blob();
      const url = URL.createObjectURL(blob), link = document.createElement('a');
      const serverName = response.headers.get('Content-Disposition')?.match(/filename="?([^";]+)"?/i)?.[1];
      link.href = url; link.download = serverName || `ITSC_${type}.${format}`; document.body.appendChild(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
      notify(`Reporte ${format === 'pdf' ? 'PDF' : 'Excel'} descargado correctamente.`);
    } catch (err) { notify(message(err), true); } finally { setDownloading(''); }
  }
  return <section className="panel"><div className="panel-heading"><div><span className="eyebrow muted">INFORMACIÓN INSTITUCIONAL</span><h2>Reportes para consulta y presentación</h2></div><span className="report-symbol" aria-hidden="true">▤</span></div><p className="subtle">Selecciona el reporte. Los filtros de gestión, carrera y grupo de esta pantalla se aplican a la descarga.</p><div className="operation-selector"><label className="field"><span>Tipo de reporte</span><select value={type} onChange={event => setType(event.target.value)} disabled={!!downloading}>{allowed.map(report => <option key={report.value} value={report.value}>{report.label}</option>)}</select></label></div><div className="report-cards"><div className="report-card"><span className="file-label file-pdf">PDF</span><h3>Documento para presentar</h3><p>Cabecera institucional y registros de la selección actual.</p><button className="button" type="button" disabled={!!downloading} onClick={() => download('pdf')}>{downloading === 'pdf' ? 'Generando PDF…' : 'Descargar PDF ↓'}</button></div><div className="report-card"><span className="file-label file-xlsx">XLSX</span><h3>Hoja de cálculo</h3><p>Datos organizados en columnas para consultar en Excel.</p><button className="button secondary" type="button" disabled={!!downloading} onClick={() => download('xlsx')}>{downloading === 'xlsx' ? 'Generando Excel…' : 'Descargar Excel ↓'}</button></div></div></section>;
}
