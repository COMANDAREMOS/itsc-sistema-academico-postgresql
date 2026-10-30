'use client';

import { useEffect, useRef, useState } from 'react';
import { api, params } from '../lib/api';

export type Row = Record<string, any>;
export type User = { id: number; usuario: string; nombre: string; rol: string; docente_id: number | null };
export type Option = { value: string | number; label: string; [key: string]: any };
export type Field = { name: string; label: string; type: string; required?: boolean; source?: string; options?: (Option | string)[]; min?: number; max?: number; step?: number; maxLength?: number };
export type Module = { key: string; title: string; description?: string; desc?: string; section: string; readonly?: boolean; editable?: boolean; deletable?: boolean; roles?: string[]; fields: Field[] };
export type Column = { key: string; label: string };
export type Listing = { rows: Row[]; total: number; page: number; pageSize: number; columns: (Column | string)[] };
export type NoticeFn = (message: string, error?: boolean) => void;
export type Filters = { periodo_id: string; carrera_id: string; grupo_id: string };

export function message(error: unknown) { return error instanceof Error ? error.message : 'No se pudo completar la operación.'; }
export function optionsOf(value: any): Option[] {
  const rows = Array.isArray(value) ? value : value?.options || value?.rows || [];
  return rows.map((item: any) => typeof item === 'string' ? { value: item, label: item } : { ...item, value: item.value ?? item.id, label: item.label ?? item.nombre ?? item.name ?? String(item.value ?? item.id) });
}
export function titleOf(key: string) { return key.replace(/_/g, ' ').replace(/^./, s => s.toUpperCase()); }
export function human(value: any): string {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'boolean') return value ? 'Sí' : 'No';
  if (typeof value === 'object') return value.label || value.nombre || JSON.stringify(value);
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(value)) {
    const day = value.slice(0, 10).split('-').reverse().join('/');
    return /T00:00:00/.test(value) ? day : `${day} ${value.slice(11, 16)}`;
  }
  return String(value);
}
export function localInstant(value: any): string {
  if (value === null || value === undefined || value === '') return '—';
  const instant = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(instant.valueOf())) return human(value);
  return new Intl.DateTimeFormat('es-BO', {
    timeZone: 'America/La_Paz', day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).format(instant);
}
export function Loading({ label = 'Cargando información…' }: { label?: string }) { return <div className="loading-state" role="status"><span className="spinner" />{label}</div>; }
export function Empty({ text = 'Todavía no hay registros para esta selección.' }: { text?: string }) { return <div className="empty"><span className="empty-symbol" aria-hidden="true">▤</span><p>{text}</p></div>; }
export function Notice({ text, error = false, onClose }: { text: string; error?: boolean; onClose?: () => void }) { return <div className={`notice ${error ? 'error' : 'ok'}`} role={error ? 'alert' : 'status'}><span>{text}</span>{onClose && <button className="text-button" type="button" onClick={onClose} aria-label="Cerrar mensaje">×</button>}</div>; }

export function DataTable({ rows, columns, actions, selectable, selected, onSelect, caption, instantColumns = [] }: { rows: Row[]; columns?: (Column | string)[]; actions?: (row: Row) => React.ReactNode; selectable?: (row: Row) => string; selected?: Set<string>; onSelect?: (id: string, checked: boolean) => void; caption?: string; instantColumns?: string[] }) {
  const cols: Column[] = (columns?.length ? columns : Object.keys(rows[0] || {}).filter(key => !['data', '_count'].includes(key))).map(col => typeof col === 'string' ? { key: col, label: titleOf(col) } : col).filter(col => !/password|hash|token/i.test(col.key));
  if (!rows.length) return <Empty />;
  return <div className="table-wrap"><table><caption className="sr-only">{caption || 'Listado de registros'}</caption><thead><tr>{selectable && <th scope="col">Seleccionar</th>}{cols.map(col => <th key={col.key} scope="col">{col.label}</th>)}{actions && <th scope="col">Acciones</th>}</tr></thead><tbody>{rows.map((row, index) => {
    const key = selectable ? selectable(row) : String(row.id ?? `${row.inscripcion_id ?? ''}-${row.evaluacion_id ?? row.sesion_id ?? ''}-${index}`);
    return <tr key={key}>{selectable && <td><input type="checkbox" checked={selected?.has(key) || false} onChange={event => onSelect?.(key, event.target.checked)} aria-label={`Seleccionar ${row.estudiante || row.nombre || row.registro || key}`} /></td>}{cols.map(col => {
      const display = instantColumns.includes(col.key) ? localInstant(row[col.key]) : human(row[col.key]);
      return <td key={col.key} title={display}>{/estado|rol/.test(col.key) && row[col.key] != null ? <span className={`status-badge status-${String(row[col.key]).toLowerCase()}`}>{display}</span> : col.key === 'dia' && Number(row[col.key]) >= 1 && Number(row[col.key]) <= 7 ? ['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'][Number(row[col.key]) - 1] : display}</td>;
    })}{actions && <td className="row-actions">{actions(row)}</td>}</tr>;
  })}</tbody></table></div>;
}

export function Pagination({ page, total, pageSize, onPage }: { page: number; total: number; pageSize: number; onPage: (page: number) => void }) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  return <div className="table-footer pagination"><span>Página {page} de {pages} · {total.toLocaleString('es-BO')} registros</span><div><button type="button" className="button secondary small-button" disabled={page <= 1} onClick={() => onPage(page - 1)}>← Anterior</button><button type="button" className="button secondary small-button" disabled={page >= pages} onClick={() => onPage(page + 1)}>Siguiente →</button></div></div>;
}

export function QuerySelect({ label, source, value, onChange, filters = {}, required = false, name, disabled = false, searchable = true, placeholder = 'Seleccionar…' }: { label: string; source: string; value: string; onChange: (value: string) => void; filters?: Record<string, unknown>; required?: boolean; name?: string; disabled?: boolean; searchable?: boolean; placeholder?: string }) {
  const [options, setOptions] = useState<Option[]>([]), [search, setSearch] = useState(''), [loading, setLoading] = useState(false), [error, setError] = useState('');
  const query = params({ ...filters, q: search });
  useEffect(() => {
    let active = true;
    const timer = setTimeout(() => { setLoading(true); setError(''); api(`/opciones/${encodeURIComponent(source)}?${query}`).then(data => { if (active) setOptions(optionsOf(data)); }).catch(err => { if (active) setError(message(err)); }).finally(() => { if (active) setLoading(false); }); }, search ? 200 : 0);
    return () => { active = false; clearTimeout(timer); };
  }, [source, query]);
  const fieldId = `field-${name || source}-${label.replace(/\W/g, '')}`;
  return <div className="field select-field"><label htmlFor={fieldId}>{label}{required && <b aria-label="obligatorio"> *</b>}</label>{searchable && <input className="select-search" type="search" value={search} onChange={event => setSearch(event.target.value)} placeholder="Escribe para buscar opciones…" aria-label={`Buscar ${label.toLowerCase()}`} disabled={disabled} />}
    <select id={fieldId} name={name} value={value} onChange={event => onChange(event.target.value)} required={required} disabled={disabled} aria-busy={loading} aria-describedby={error ? `${fieldId}-error` : undefined}><option value="">{loading ? 'Cargando opciones…' : placeholder}</option>{value && !options.some(option => String(option.value) === String(value)) && <option value={value}>Registro #{value}</option>}{options.map((option, index) => <option key={`${option.value}-${index}`} value={option.value}>{option.label}</option>)}</select>
    {error && <small className="field-error" id={`${fieldId}-error`}>{error}</small>}
  </div>;
}

export function RecordFields({ fields, values, onChange, disabled = false }: { fields: Field[]; values: Row; onChange: (key: string, value: string) => void; disabled?: boolean }) {
  const context: Row = {};
  ['periodo_id', 'carrera_id', 'grupo_id', 'oferta_id', 'matricula_id'].forEach(key => { if (values[key]) context[key] = values[key]; });
  return <div className="form-grid">{fields.map(field => {
    const value = values[field.name] == null ? '' : String(values[field.name]);
    if (field.source) return <QuerySelect key={field.name} name={field.name} label={field.label} source={field.source} value={value} onChange={next => onChange(field.name, next)} filters={context} required={field.required !== false} disabled={disabled} />;
    if (field.options || field.type === 'enum') return <label key={field.name} className="field"><span>{field.label}{field.required !== false && <b> *</b>}</span><select name={field.name} required={field.required !== false} value={value} onChange={event => onChange(field.name, event.target.value)} disabled={disabled}><option value="">Seleccionar…</option>{(field.options || []).map((option, index) => typeof option === 'string' ? <option key={index} value={option}>{option}</option> : <option key={index} value={option.value ?? (option as any).id}>{option.label}</option>)}</select></label>;
    const type = field.type === 'decimal' ? 'number' : ['date', 'datetime-local', 'time', 'email', 'number', 'password', 'tel', 'url'].includes(field.type) ? field.type : 'text';
    let displayValue = value;
    if (type === 'date') displayValue = value.slice(0, 10);
    if (type === 'time' && value.includes('T')) displayValue = value.slice(11, 16);
    if (type === 'datetime-local' && value.includes('Z')) { const date = new Date(value); displayValue = new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 16); }
    return <label className="field" key={field.name}><span>{field.label}{field.required !== false && <b> *</b>}</span><input type={type} name={field.name} value={displayValue} onChange={event => onChange(field.name, event.target.value)} required={field.required !== false} min={field.min ?? (type === 'number' ? 0 : undefined)} max={field.max} maxLength={field.maxLength ?? (type === 'password' ? 128 : 500)} step={field.step ?? (field.type === 'decimal' ? '0.001' : type === 'number' ? '1' : undefined)} autoComplete={type === 'password' ? 'new-password' : undefined} disabled={disabled} />{type === 'password' && <small>Usa al menos 12 caracteres.</small>}</label>;
  })}</div>;
}

export function Modal({ title, children, onClose, busy = false }: { title: string; children: React.ReactNode; onClose: () => void; busy?: boolean }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => { const dialog = ref.current; dialog?.showModal(); return () => { dialog?.close(); }; }, []);
  return <dialog className="record-dialog" ref={ref} onCancel={event => { event.preventDefault(); if (!busy) onClose(); }} aria-labelledby="dialog-title"><div className="dialog-heading"><h2 id="dialog-title">{title}</h2><button type="button" className="text-button dialog-close" aria-label="Cerrar formulario" onClick={onClose} disabled={busy}>×</button></div>{children}</dialog>;
}
