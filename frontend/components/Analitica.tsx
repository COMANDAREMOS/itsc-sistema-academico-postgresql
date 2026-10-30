'use client';

import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { DataTable, Empty, human, Loading, message, Notice, NoticeFn, Row } from './ui';

export default function Analitica({ notify }: { notify: NoticeFn }) {
  const [data, setData] = useState<Row | null>(null), [loading, setLoading] = useState(true), [updating, setUpdating] = useState(false), [error, setError] = useState(''), [revision, setRevision] = useState(0);
  useEffect(() => {
    let active = true; setLoading(true); setError('');
    api('/analitica').then(result => { if (active) setData(result); }).catch(err => { if (active) setError(message(err)); }).finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [revision]);
  async function update() {
    setUpdating(true);
    try { const result = await api('/analitica/actualizar', { method: 'POST' }); notify(result.message || 'Información analítica actualizada correctamente.'); setRevision(value => value + 1); } catch (err) { notify(message(err), true); } finally { setUpdating(false); }
  }
  const kpis: Row[] = data?.kpis || [], matriculas: Row[] = data?.matriculas || [], recaudacion: Row[] = data?.recaudacion || [], rendimiento: Row[] = data?.rendimiento || [], ejecuciones: Row[] = data?.ejecuciones || [];
  const hasResults = rendimiento.some(row => Number(row.inscripciones) > 0 && row.promedio != null);
  return <>
    <section className="panel analytics-intro"><div className="panel-heading"><div><span className="eyebrow muted">ANÁLISIS INSTITUCIONAL</span><h2>Información para tomar decisiones</h2></div><button type="button" className="button" disabled={updating || loading} onClick={update}>{updating ? 'Actualizando información…' : 'Actualizar análisis ↻'}</button></div><p className="subtle">Consulta matrículas, resultados académicos y recaudación. La actualización reúne los registros del sistema y conserva una bitácora de cada proceso.</p><div className="analytics-source-note"><span className="dot" /><span>Los indicadores muestran información almacenada en la última actualización.</span></div></section>
    {error ? <section className="panel"><Notice text={error} error /><button className="button secondary" onClick={() => setRevision(value => value + 1)}>Volver a intentar</button></section> : loading ? <section className="panel"><Loading label="Consultando la información analítica…" /></section> : <>
      {kpis.length > 0 && <div className="stats-grid">{kpis.map((item, index) => <section className={`stat ${index === kpis.length - 1 ? 'accent' : ''}`} key={item.label || index}><span>{item.label}</span><strong>{typeof item.value === 'number' ? item.value.toLocaleString('es-BO', { maximumFractionDigits: 2 }) : human(item.value)}</strong><small>{item.hint || 'Última actualización'}</small></section>)}</div>}
      <div className="analytics-columns"><section className="panel records-panel"><div className="panel-heading"><div><span className="eyebrow muted">ADMISIÓN</span><h2>Matrículas por gestión y carrera</h2></div></div><DataTable rows={matriculas} columns={[{ key: 'gestion', label: 'Gestión' }, { key: 'carrera', label: 'Carrera' }, { key: 'total', label: 'Matrículas' }]} caption="Matrículas por gestión y carrera" /></section><section className="panel records-panel"><div className="panel-heading"><div><span className="eyebrow muted">CAJA</span><h2>Recaudación mensual</h2></div></div><DataTable rows={recaudacion} columns={[{ key: 'mes', label: 'Mes' }, { key: 'total', label: 'Recaudación (Bs)' }]} caption="Recaudación por mes" /></section></div>
      <section className="panel records-panel"><div className="panel-heading"><div><span className="eyebrow muted">RESULTADOS ACADÉMICOS</span><h2>Rendimiento por carrera</h2></div></div>{!hasResults ? <Empty text="Todavía no hay resultados finales para analizar. Completa las notas y la asistencia, realiza el cierre académico y actualiza el análisis." /> : <DataTable rows={rendimiento} columns={[{ key: 'carrera', label: 'Carrera' }, { key: 'inscripciones', label: 'Resultados registrados' }, { key: 'promedio', label: 'Promedio' }, { key: 'aprobados', label: 'Aprobados' }]} caption="Rendimiento académico por carrera" />}</section>
      <details className="panel analytics-model"><summary><span><span className="eyebrow muted">ORGANIZACIÓN DEL ANÁLISIS</span><strong>Vista del modelo estrella</strong></span><span aria-hidden="true">＋</span></summary><div className="star-model"><div className="star-dimension"><span>DIMENSIONES</span><strong>Tiempo y gestión</strong><p>Permiten comparar la información entre períodos.</p></div><div className="star-dimension"><span>DIMENSIONES</span><strong>Comunidad académica</strong><p>Carreras, estudiantes, docentes y materias.</p></div><div className="star-facts"><span>HECHOS</span><strong>Matrículas · Resultados · Pagos</strong><p>Medidas de la actividad académica y administrativa.</p></div></div><p className="subtle model-caption">Las dimensiones describen el contexto; los hechos reúnen las medidas que se consultan en los indicadores.</p></details>
      <section className="panel records-panel"><div className="panel-heading"><div><span className="eyebrow muted">TRAZABILIDAD</span><h2>Historial de actualizaciones</h2></div></div><DataTable rows={ejecuciones} instantColumns={['inicio', 'fin']} columns={[{ key: 'id', label: 'Proceso' }, { key: 'inicio', label: 'Inicio' }, { key: 'fin', label: 'Fin' }, { key: 'estado', label: 'Estado' }, { key: 'matriculas', label: 'Matrículas' }, { key: 'resultados', label: 'Resultados' }, { key: 'pagos', label: 'Pagos' }]} caption="Bitácora de actualización del análisis institucional" /></section>
    </>}
  </>;
}
