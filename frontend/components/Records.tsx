'use client';

import { useEffect, useState } from 'react';
import { api, params } from '../lib/api';
import { DataTable, Empty, Filters, Listing, Loading, message, Modal, Module, Notice, NoticeFn, Pagination, RecordFields, Row } from './ui';

export default function Records({ module, filters, notify }: { module: Module; filters: Filters; notify: NoticeFn }) {
  const [data, setData] = useState<Listing | null>(null), [loading, setLoading] = useState(true), [error, setError] = useState('');
  const [search, setSearch] = useState(''), [query, setQuery] = useState(''), [page, setPage] = useState(1), [revision, setRevision] = useState(0);
  const [editing, setEditing] = useState<Row | null>(null), [formOpen, setFormOpen] = useState(false), [values, setValues] = useState<Row>({}), [saving, setSaving] = useState(false), [formError, setFormError] = useState('');
  const filterKey = params(filters);
  useEffect(() => { setPage(1); }, [filterKey]);
  useEffect(() => {
    let active = true;
    setLoading(true); setError('');
    api<Listing>(`/datos/${module.key}?${params({ ...filters, q: query, page, pageSize: 20 })}`).then(result => { if (active) setData({ ...result, page: result.page || page, pageSize: result.pageSize || 20, rows: result.rows || [] }); }).catch(err => { if (active) setError(message(err)); }).finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [module.key, filterKey, query, page, revision]);

  async function openForm(row?: Row) {
    setFormError(''); setEditing(row || null);
    if (row) {
      try { const detail = await api<Row>(`/datos/${module.key}/${row.id}`); setValues(detail.data || detail); setFormOpen(true); } catch (err) { notify(message(err), true); }
    } else {
      const initial: Row = {};
      module.fields.forEach(field => {
        if (field.type === 'date') initial[field.name] = new Date().toLocaleDateString('en-CA');
        if (filters[field.name as keyof Filters]) initial[field.name] = filters[field.name as keyof Filters];
      });
      setValues(initial); setFormOpen(true);
    }
  }
  async function save(event: React.FormEvent) {
    event.preventDefault(); setSaving(true); setFormError('');
    const body: Row = {};
    module.fields.forEach(field => {
      const value = values[field.name];
      if ((value === '' || value == null) && field.required === false) { body[field.name] = null; return; }
      body[field.name] = field.source || ['number', 'decimal', 'integer'].includes(field.type) ? (value === '' || value == null ? value : Number(value)) : value;
    });
    try {
      const result = await api(`/datos/${module.key}${editing ? `/${editing.id}` : ''}`, { method: editing ? 'PATCH' : 'POST', body: JSON.stringify(body) });
      setFormOpen(false); setRevision(value => value + 1); notify(result.message || 'Registro guardado correctamente.');
    } catch (err) { setFormError(message(err)); } finally { setSaving(false); }
  }
  async function remove(row: Row) {
    if (!window.confirm(`¿Confirmas retirar el registro #${row.id}? El sistema comprobará que sus relaciones permitan la operación.`)) return;
    try { const result = await api(`/datos/${module.key}/${row.id}`, { method: 'DELETE' }); notify(result.message || 'Registro retirado correctamente.'); setRevision(value => value + 1); } catch (err) { notify(message(err), true); }
  }
  async function toggleUser(row: Row) {
    const activo = row.activo === 1 || row.activo === true;
    if (!window.confirm(`¿Confirmas ${activo ? 'deshabilitar' : 'habilitar'} el acceso de ${row.usuario}?`)) return;
    try { const result = await api(`/datos/usuarios/${row.id}`, { method: 'PATCH', body: JSON.stringify({ activo: activo ? 0 : 1 }) }); notify(result.message || 'Estado de acceso actualizado.'); setRevision(value => value + 1); } catch (err) { notify(message(err), true); }
  }
  const canCreate = !module.readonly && module.fields?.length > 0;
  const hasActions = module.editable || module.deletable || module.key === 'usuarios';

  return <>
    <section className="panel records-panel">
      <div className="panel-heading"><div><span className="eyebrow muted">REGISTROS</span><h2>{module.title}<span className="count">{data?.total ?? '…'}</span></h2></div><div className="panel-tools">{canCreate && <button type="button" className="button" onClick={() => openForm()}>＋ Nuevo registro</button>}{module.key === 'boletin' && <button type="button" className="button secondary" onClick={() => window.print()}>Imprimir boletín</button>}<button type="button" className="icon-button" aria-label="Actualizar listado" onClick={() => setRevision(value => value + 1)} disabled={loading}>↻</button></div></div>
      <form className="search server-search records-search" onSubmit={event => { event.preventDefault(); setPage(1); setQuery(search); }}><input type="search" placeholder="Buscar en todos los registros" value={search} onChange={event => setSearch(event.target.value)} aria-label={`Buscar ${module.title.toLowerCase()}`} /><button className="text-button" type="submit">Buscar</button>{query && <button type="button" className="text-button" aria-label="Limpiar búsqueda" onClick={() => { setSearch(''); setQuery(''); setPage(1); }}>×</button>}</form>
      {error ? <div className="table-error"><Notice text={error} error /><button className="button secondary" onClick={() => setRevision(value => value + 1)}>Volver a intentar</button></div> : loading ? <Loading /> : data && <><DataTable rows={data.rows} columns={data.columns} instantColumns={module.key === 'auditoria' ? ['fecha'] : []} caption={module.title} actions={hasActions ? row => <>{module.editable && <button type="button" className="table-action" onClick={() => openForm(row)} aria-label={`Editar registro ${row.id}`}>Editar</button>}{module.deletable && <button type="button" className="table-action danger-link" onClick={() => remove(row)}>Retirar</button>}{module.key === 'usuarios' && <button type="button" className="table-action" onClick={() => toggleUser(row)}>{row.activo === 1 || row.activo === true ? 'Deshabilitar' : 'Habilitar'}</button>}</> : undefined} /><Pagination page={data.page} total={data.total} pageSize={data.pageSize} onPage={setPage} /></>}
    </section>
    {formOpen && <Modal title={editing ? `Editar registro #${editing.id}` : `Nuevo registro · ${module.title}`} onClose={() => setFormOpen(false)} busy={saving}><form className="entry-form" onSubmit={save}>{formError && <Notice text={formError} error />}<RecordFields fields={module.fields} values={values} onChange={(key, value) => setValues(previous => ({ ...previous, [key]: value }))} disabled={saving} /><div className="form-footer"><span>* Campos obligatorios</span><div className="button-group"><button className="button secondary" type="button" onClick={() => setFormOpen(false)} disabled={saving}>Cancelar</button><button className="button" type="submit" disabled={saving}>{saving ? 'Guardando…' : 'Guardar registro →'}</button></div></div></form></Modal>}
  </>;
}
