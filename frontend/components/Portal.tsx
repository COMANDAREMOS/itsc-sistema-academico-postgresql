'use client';

import { useCallback, useEffect, useState } from 'react';
import { api, params } from '../lib/api';
import Dashboard from './Dashboard';
import Analitica from './Analitica';
import Records from './Records';
import { GroupEnrollment, Reports, Roster } from './Operations';
import { Filters, Loading, message, Module, Notice, QuerySelect, Row, User } from './ui';

function Brand({ onClick }: { onClick?: () => void }) {
  return <a className="brand" href="/" onClick={onClick ? event => { event.preventDefault(); onClick(); } : undefined}><img className="institutional-logo" src="/assets/logo-itsc-v2.png" alt="Logotipo del Instituto Tecnológico Santa Cruz" width="74" height="74" /><span>TECNOLÓGICO<br /><strong>SANTA CRUZ</strong></span></a>;
}

function ThemeButton({ dark, onToggle }: { dark: boolean; onToggle: () => void }) {
  return <button className="theme-toggle" type="button" onClick={onToggle} aria-pressed={dark} aria-label={`Cambiar a modo ${dark ? 'claro' : 'oscuro'}`}><span aria-hidden="true">{dark ? '☀' : '☾'}</span><span>Modo {dark ? 'claro' : 'oscuro'}</span></button>;
}

function Login({ onLogin, dark, onToggle, info }: { onLogin: (user: User) => void; dark: boolean; onToggle: () => void; info?: string }) {
  const [username, setUsername] = useState(''), [password, setPassword] = useState(''), [error, setError] = useState(''), [loading, setLoading] = useState(false);
  async function submit(event: React.FormEvent) {
    event.preventDefault(); setLoading(true); setError('');
    try { const result = await api('/auth/login', { method: 'POST', body: JSON.stringify({ usuario: username.trim(), password }) }); setPassword(''); onLogin(result.user || result); } catch (err) { setError(message(err)); } finally { setLoading(false); }
  }
  return <main className="login-shell"><section className="login-story"><Brand /><div className="story-copy"><span className="eyebrow">GESTIÓN ACADÉMICA</span><h1>El siguiente paso<br />empieza aquí.</h1><p>Una visión clara de la vida académica.<br />Estudiantes, aprendizaje y gestión en un solo lugar.</p><div className="story-stats"><div><strong>Formación</strong><span>técnica y profesional</span></div><div><strong>Gestión</strong><span>académica institucional</span></div></div></div><small>Aplicación local de práctica · Datos ficticios</small></section><section className="login-form"><div className="login-card"><div className="login-theme-bar"><ThemeButton dark={dark} onToggle={onToggle} /></div><span className="eyebrow muted">BIENVENIDO</span><h2>Ingresa a tu espacio</h2><p className="subtle">Usa el acceso asignado por administración.</p>{error ? <Notice text={error} error /> : info ? <Notice text={info} /> : null}<form onSubmit={submit}><label className="field"><span>Usuario</span><input name="usuario" autoComplete="username" required autoFocus maxLength={60} value={username} onChange={event => setUsername(event.target.value)} disabled={loading} /></label><label className="field"><span>Contraseña</span><input name="password" type="password" autoComplete="current-password" required value={password} onChange={event => setPassword(event.target.value)} disabled={loading} maxLength={128} /></label><button className="button full" type="submit" disabled={loading}>{loading ? 'Ingresando…' : 'Ingresar'}<span aria-hidden="true">→</span></button></form><p className="login-help">¿Necesitas acceso? Solicítalo al administrador del sistema.</p><div className="demo-note"><span className="dot" />Portal académico institucional</div></div></section></main>;
}

function PasswordForm({ user, notify, onRelogin }: { user: User; notify: (text: string, error?: boolean) => void; onRelogin: (text: string) => void }) {
  const [values, setValues] = useState({ actual: '', nueva: '', confirmacion: '' }), [saving, setSaving] = useState(false), [error, setError] = useState('');
  async function save(event: React.FormEvent) {
    event.preventDefault(); setError('');
    if (values.nueva !== values.confirmacion) { setError('La nueva contraseña y su confirmación deben coincidir.'); return; }
    setSaving(true);
    try { const result = await api('/auth/password', { method: 'POST', body: JSON.stringify(values) }); setValues({ actual: '', nueva: '', confirmacion: '' }); if (result.relogin) onRelogin(result.message || 'Contraseña actualizada. Ingresa con tu nueva contraseña.'); else notify(result.message || 'Contraseña actualizada correctamente.'); } catch (err) { setError(message(err)); } finally { setSaving(false); }
  }
  return <section className="panel account-panel"><div className="panel-heading"><div><span className="eyebrow muted">ACCESO PERSONAL</span><h2>Mi contraseña</h2></div><span className="pill">{user.rol}</span></div><p className="subtle">{user.nombre} · {user.usuario}</p>{error && <Notice text={error} error />}<form onSubmit={save}><div className="form-grid"><label className="field field-full"><span>Contraseña actual</span><input name="actual" type="password" autoComplete="current-password" required value={values.actual} onChange={event => setValues(previous => ({ ...previous, actual: event.target.value }))} disabled={saving} maxLength={128} /></label><label className="field"><span>Nueva contraseña</span><input name="nueva" type="password" autoComplete="new-password" minLength={12} maxLength={128} required value={values.nueva} onChange={event => setValues(previous => ({ ...previous, nueva: event.target.value }))} disabled={saving} /><small>Como mínimo, 12 caracteres.</small></label><label className="field"><span>Repite la nueva contraseña</span><input name="confirmacion" type="password" autoComplete="new-password" minLength={12} maxLength={128} required value={values.confirmacion} onChange={event => setValues(previous => ({ ...previous, confirmacion: event.target.value }))} disabled={saving} /></label></div><div className="form-footer"><span>Tu contraseña es personal.</span><button className="button" disabled={saving}>{saving ? 'Guardando…' : 'Actualizar contraseña →'}</button></div></form></section>;
}

const filterPages = new Set(['inicio', 'grupos', 'integrantes', 'grupo_materias', 'ofertas', 'inscripcion_grupal', 'horarios', 'matriculas', 'inscripciones', 'notas_grupo', 'asistencia_grupo', 'evaluaciones', 'notas', 'sesiones', 'asistencias', 'excepciones', 'cierres', 'recuperaciones', 'boletin', 'cargos', 'pagos', 'saldos', 'documentos', 'tramites', 'pasantias', 'reportes']);

export default function Portal() {
  const [user, setUser] = useState<User | null>(null), [initializing, setInitializing] = useState(true), [modules, setModules] = useState<Module[]>([]), [catalogLoading, setCatalogLoading] = useState(false), [catalogError, setCatalogError] = useState(''), [catalogRevision, setCatalogRevision] = useState(0);
  const [page, setPage] = useState('inicio'), [filters, setFilters] = useState<Filters>({ periodo_id: '', carrera_id: '', grupo_id: '' }), [dark, setDark] = useState(false), [mobileNav, setMobileNav] = useState(false), [loggingOut, setLoggingOut] = useState(false);
  const [notice, setNotice] = useState<{ text: string; error: boolean } | null>(null);
  const notify = useCallback((text: string, error = false) => setNotice({ text, error }), []);
  useEffect(() => {
    const sync = () => { const url = new URL(window.location.href); setPage(url.searchParams.get('p') || 'inicio'); setFilters({ periodo_id: url.searchParams.get('periodo_id') || '', carrera_id: url.searchParams.get('carrera_id') || '', grupo_id: url.searchParams.get('grupo_id') || '' }); };
    sync(); setDark(document.documentElement.dataset.theme === 'dark');
    const expired = () => { setUser(null); setModules([]); setNotice(null); };
    window.addEventListener('popstate', sync); window.addEventListener('itsc-session-expired', expired);
    api('/auth/me').then(result => setUser(result.user || result)).catch(() => setUser(null)).finally(() => setInitializing(false));
    return () => { window.removeEventListener('popstate', sync); window.removeEventListener('itsc-session-expired', expired); };
  }, []);
  useEffect(() => {
    if (!user) return;
    let active = true; setCatalogLoading(true); setCatalogError('');
    api('/catalogo').then(result => { if (active) setModules((Array.isArray(result) ? result : result.modules || []).map((module: any) => ({ ...module, description: module.description || module.desc, fields: module.fields || [], section: module.section || 'INSTITUCIÓN' }))); }).catch(err => { if (active) setCatalogError(message(err)); }).finally(() => { if (active) setCatalogLoading(false); });
    return () => { active = false; };
  }, [user?.id, catalogRevision]);
  useEffect(() => { if (!user || catalogLoading || !modules.length) return; if (!['inicio', 'cuenta'].includes(page) && !modules.some(module => module.key === page)) { setPage('inicio'); const url = new URL(window.location.href); url.searchParams.delete('p'); window.history.replaceState({}, '', url); notify('La pantalla solicitada no está disponible para tu acceso.', true); } }, [user, page, catalogLoading, modules, notify]);

  const navigate = useCallback((next: string) => { setPage(next); setNotice(null); setMobileNav(false); const url = new URL(window.location.href); next === 'inicio' ? url.searchParams.delete('p') : url.searchParams.set('p', next); window.history.pushState({}, '', url); window.scrollTo({ top: 0, behavior: 'instant' }); }, []);
  function updateFilters(next: Partial<Filters>) {
    setFilters(previous => { const result = { ...previous, ...next }; if ('periodo_id' in next || 'carrera_id' in next) result.grupo_id = ''; const url = new URL(window.location.href); Object.entries(result).forEach(([key, value]) => value ? url.searchParams.set(key, value) : url.searchParams.delete(key)); window.history.replaceState({}, '', url); return result; });
  }
  function toggleTheme() { const next = !dark; setDark(next); document.documentElement.dataset.theme = next ? 'dark' : 'light'; try { localStorage.setItem('itsc-theme', next ? 'dark' : 'light'); } catch { /* El tema sigue funcionando si el navegador bloquea el almacenamiento. */ } }
  async function logout() { setLoggingOut(true); try { await api('/auth/logout', { method: 'POST' }); setUser(null); setModules([]); setNotice(null); setPage('inicio'); window.history.replaceState({}, '', '/'); } catch (err) { notify(message(err), true); } finally { setLoggingOut(false); } }
  function login(nextUser: User) { setUser(nextUser); setPage('inicio'); setNotice(null); window.history.replaceState({}, '', '/'); }

  if (initializing) return <main className="standalone loading-screen"><img src="/assets/logo-itsc-v2.png" alt="Instituto Tecnológico Santa Cruz" width="100" height="100" /><Loading label="Abriendo el portal académico…" /></main>;
  if (!user) return <Login onLogin={login} dark={dark} onToggle={toggleTheme} info={notice?.text} />;

  const currentModule = modules.find(module => module.key === page);
  const title = page === 'inicio' ? 'Panel por gestión' : page === 'cuenta' ? 'Mi contraseña' : currentModule?.title || 'Portal académico';
  const description = page === 'inicio' ? 'Organización institucional, gestión académica y seguimiento estudiantil.' : page === 'cuenta' ? 'Actualiza la contraseña de tu acceso personal.' : currentModule?.description;
  const sections = [...new Set(['INSTITUCIÓN', ...modules.map(module => module.section)])];
  const activeSection = page === 'inicio' ? 'INSTITUCIÓN' : currentModule?.section;
  const date = new Intl.DateTimeFormat('es-BO', { timeZone: 'America/La_Paz', day: '2-digit', month: '2-digit', year: 'numeric' }).format(new Date());

  return <><a className="skip-link" href="#contenido">Ir al contenido</a><aside className={`sidebar ${mobileNav ? 'mobile-nav-open' : ''}`}><div className="brand-row"><Brand onClick={() => navigate('inicio')} /><button className="mobile-menu-button" type="button" onClick={() => setMobileNav(value => !value)} aria-expanded={mobileNav} aria-controls="main-navigation">☰ Menú</button></div><div className="workspace-label"><span className="dot" /> Gestión académica</div><nav id="main-navigation" aria-label="Navegación principal">{sections.map(section => <details className="nav-section" key={section} open={section === activeSection}><summary>{section}</summary>{section === 'INSTITUCIÓN' && <a href="/" className={`nav-link ${page === 'inicio' ? 'active' : ''}`} aria-current={page === 'inicio' ? 'page' : undefined} onClick={event => { event.preventDefault(); navigate('inicio'); }}>Panel institucional</a>}{modules.filter(module => module.section === section).map(module => <a key={module.key} href={`/?p=${module.key}`} className={`nav-link ${page === module.key ? 'active' : ''}`} aria-current={page === module.key ? 'page' : undefined} onClick={event => { event.preventDefault(); navigate(module.key); }}>{module.title}</a>)}</details>)}</nav><div className="sidebar-footer"><span className="avatar">{user.nombre?.slice(0, 1).toUpperCase()}</span><div><strong>{user.nombre}</strong><small>{user.rol}</small></div><button className="text-button account-icon" onClick={() => navigate('cuenta')} title="Cambiar contraseña" aria-label="Cambiar contraseña">⚙</button></div></aside>
    <div className="app-shell"><header className="topbar"><span>Instituto Tecnológico Santa Cruz<span className="divider">/</span><strong>{title}</strong></span><div className="top-actions"><ThemeButton dark={dark} onToggle={toggleTheme} /><a className="text-button diagram-link" href="/diagrama-clases.html" target="_blank" rel="noopener noreferrer">Diagrama de clases ↗</a><button className="text-button" onClick={() => navigate('cuenta')}>Mi cuenta</button><button className="text-button" onClick={logout} disabled={loggingOut}>{loggingOut ? 'Saliendo…' : 'Salir ↗'}</button></div></header><main className="content" id="contenido"><div className="page-heading"><div><div className="eyebrow muted">{date}<span> / </span>PORTAL ACADÉMICO</div><h1>{title}</h1><p className="subtle">{description}</p></div></div>{notice && <Notice text={notice.text} error={notice.error} onClose={() => setNotice(null)} />}
      {catalogError ? <section className="panel"><Notice text={catalogError} error /><button className="button secondary" onClick={() => setCatalogRevision(value => value + 1)}>Volver a intentar</button></section> : catalogLoading ? <section className="panel"><Loading label="Cargando tus módulos…" /></section> : <>
        {filterPages.has(page) && <section className="panel filters-panel" aria-label="Filtros de gestión"><div className="filters-heading"><span className="eyebrow muted">SELECCIÓN ACADÉMICA</span>{(filters.periodo_id || filters.carrera_id || filters.grupo_id) && <button className="text-button" onClick={() => updateFilters({ periodo_id: '', carrera_id: '', grupo_id: '' })}>Limpiar filtros</button>}</div><div className={`filters-grid ${page === 'inicio' ? 'filters-single' : ''}`}><QuerySelect label="Gestión / período" source="periodos" value={filters.periodo_id} onChange={value => updateFilters({ periodo_id: value })} searchable={false} placeholder="Todas las gestiones" />{page !== 'inicio' && <><QuerySelect label="Carrera" source="carreras" value={filters.carrera_id} onChange={value => updateFilters({ carrera_id: value })} searchable={false} placeholder="Todas las carreras" /><QuerySelect label="Grupo" source="grupos" value={filters.grupo_id} onChange={value => updateFilters({ grupo_id: value })} filters={{ periodo_id: filters.periodo_id, carrera_id: filters.carrera_id }} searchable={false} placeholder="Todos los grupos" /></>}</div></section>}
        {page === 'inicio' ? <Dashboard filters={{ periodo_id: filters.periodo_id, carrera_id: '', grupo_id: '' }} modules={modules} navigate={navigate} /> : page === 'cuenta' ? <PasswordForm user={user} notify={notify} onRelogin={text => { setUser(null); setModules([]); setNotice({ text, error: false }); window.history.replaceState({}, '', '/login'); }} /> : page === 'inscripcion_grupal' ? <GroupEnrollment key={page} filters={filters} notify={notify} /> : page === 'notas_grupo' || page === 'asistencia_grupo' ? <Roster key={page} type={page === 'notas_grupo' ? 'notas' : 'asistencias'} filters={filters} notify={notify} /> : page === 'analitica' ? <Analitica notify={notify} /> : page === 'reportes' ? <Reports filters={filters} modules={modules} notify={notify} /> : currentModule ? <Records key={currentModule.key} module={currentModule} filters={filterPages.has(page) ? filters : { periodo_id: '', carrera_id: '', grupo_id: '' }} notify={notify} /> : <section className="panel"><Loading /></section>}
      </>}
    </main><footer className="app-footer"><span>ITSC · Gestión académica</span><span>Aplicación local · Datos ficticios</span></footer></div></>;
}
