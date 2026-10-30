'use client';

import { useEffect, useState } from 'react';
import { api, params } from '../lib/api';
import { DataTable, Empty, Filters, human, localInstant, Loading, message, Module, Notice, Row } from './ui';

export default function Dashboard({ filters, modules, navigate }: { filters: Filters; modules: Module[]; navigate: (page: string) => void }) {
  const [data, setData] = useState<Row | null>(null), [error, setError] = useState(''), [loading, setLoading] = useState(true), [revision, setRevision] = useState(0);
  const query = params(filters);
  useEffect(() => { let active = true; setLoading(true); setError(''); api(`/dashboard?${query}`).then(result => { if (active) setData(result); }).catch(err => { if (active) setError(message(err)); }).finally(() => { if (active) setLoading(false); }); return () => { active = false; }; }, [query, revision]);
  if (error) return <section className="panel"><Notice text={error} error /><button className="button secondary" onClick={() => setRevision(value => value + 1)}>Volver a intentar</button></section>;
  if (loading || !data) return <section className="panel"><Loading label="Cargando el panel institucional…" /></section>;
  const quick = [
    { key: 'estudiantes', title: 'Estudiantes', text: 'Registro y seguimiento estudiantil', style: 'quick-estudiantes', symbol: '01' },
    { key: 'notas_grupo', title: 'Planilla de notas', text: 'Evaluación y rendimiento académico', style: 'quick-notas', symbol: '02' },
    { key: 'asistencia_grupo', title: 'Planilla de asistencia', text: 'Sesiones y participación', style: 'quick-asistencias', symbol: '03' },
    { key: 'pagos', title: 'Pagos y recibos', text: 'Control de abonos y saldos', style: 'quick-pagos', symbol: '04' },
  ].filter(item => modules.some(module => module.key === item.key));
  const kpis: Row[] = Array.isArray(data.kpis) ? data.kpis : [];
  const grupos: Row[] = Array.isArray(data.grupos) ? data.grupos : [];
  const carreras: Row[] = Array.isArray(data.carreras) ? data.carreras : [];
  const actividad: Row[] = Array.isArray(data.actividad) ? data.actividad : [];
  return <>
    <section className="welcome-banner"><div><span className="eyebrow">INSTITUTO TECNOLÓGICO SANTA CRUZ</span><h2>Formación que transforma.<br />Gestión que conecta.</h2><p>La comunidad académica, organizada por gestión.<br />Una visión clara para acompañar cada etapa.</p></div><div className="banner-art"><span className="orbit" /><img className="banner-logo" src="/assets/logo-itsc-v2.png" alt="Logotipo del Instituto Tecnológico Santa Cruz" width="158" height="158" /></div></section>
    {kpis.length > 0 && <div className="stats-grid">{kpis.map((kpi, index) => <section className={`stat ${index === kpis.length - 1 ? 'accent' : ''}`} key={kpi.label || index}><span>{kpi.label}</span><strong>{typeof kpi.value === 'number' ? kpi.value.toLocaleString('es-BO') : human(kpi.value)}</strong><small>{kpi.hint || 'Gestión seleccionada'}</small></section>)}</div>}
    <div className="dashboard-columns"><section className="panel"><div className="panel-heading"><div><span className="eyebrow muted">TU ESPACIO ACADÉMICO</span><h2>Accesos principales</h2></div><span aria-hidden="true">↗</span></div><div className="quick-grid">{quick.map(item => <button className={`quick-card ${item.style}`} key={item.key} onClick={() => navigate(item.key)}><span className="quick-number">{item.symbol} / GESTIÓN INSTITUCIONAL</span><h3>{item.title}<span aria-hidden="true">↗</span></h3><p>{item.text}</p></button>)}</div>{modules.some(module => module.key === 'grupos') && <div className="dashboard-links"><button type="button" className="text-button" onClick={() => navigate('grupos')}>Ver grupos por gestión →</button><button type="button" className="text-button" onClick={() => navigate('horarios')}>Consultar horarios →</button></div>}</section><section className="panel rules-card"><span className="eyebrow muted">SEGUIMIENTO ACADÉMICO</span><h2>Cada gestión,<br />bien organizada.</h2><div className="rule"><strong>Grupos</strong><span>Por carrera, curso,<br />paralelo y turno</span></div><div className="rule"><strong>Aprendizaje</strong><span>Calificaciones<br />y asistencia</span></div><div className="rule"><strong>Trayectoria</strong><span>Matrículas, documentos<br />y servicios estudiantiles</span></div><small>Los indicadores corresponden a los registros de la selección actual.</small></section></div>
    <section className="panel records-panel"><div className="panel-heading"><div><span className="eyebrow muted">ORGANIZACIÓN ACADÉMICA</span><h2>Grupos de la gestión<span className="count">{grupos.length}</span></h2></div>{modules.some(module => module.key === 'grupos') && <button className="text-button" onClick={() => navigate('grupos')}>Administrar grupos →</button>}</div><DataTable rows={grupos} columns={['gestion','carrera','curso','paralelo','turno','estudiantes','materias','cupo','estado']} caption="Grupos de la gestión seleccionada" /></section>
    <div className="dashboard-bottom"><section className="panel"><div className="panel-heading"><div><span className="eyebrow muted">COMUNIDAD</span><h2>Matrículas por carrera</h2></div></div>{carreras.length ? <div className="career-list">{carreras.map((carrera, index) => {
      const count = Number(carrera.matriculas ?? carrera.estudiantes ?? carrera.total ?? 0);
      const max = Math.max(1, ...carreras.map(item => Number(item.matriculas ?? item.estudiantes ?? item.total ?? 0)));
      return <div className="career-item" key={carrera.id || index}><div><span>{carrera.carrera || carrera.nombre || carrera.label}</span><strong>{count}</strong></div><div className="career-track" aria-hidden="true"><span style={{ width: `${count / max * 100}%` }} /></div></div>;
    })}</div> : <Empty text="No hay matrículas para esta selección." />}</section><section className="panel"><div className="panel-heading"><div><span className="eyebrow muted">REGISTRO INSTITUCIONAL</span><h2>Actividad reciente</h2></div></div>{actividad.length ? <ul className="activity-list">{actividad.slice(0, 6).map((item, index) => <li key={item.id || index}><span className="activity-dot" /><div><strong>{item.accion || item.actividad || item.entidad}</strong><span>{item.usuario || item.nombre || ''} {item.entidad ? `· ${item.entidad}` : ''}</span><small>{localInstant(item.fecha)}</small></div></li>)}</ul> : <Empty text="Todavía no hay actividad registrada." />}</section></div>
  </>;
}
