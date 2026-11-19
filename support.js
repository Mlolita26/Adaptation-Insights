/* Adaptation Insights: standalone runtime for the Design canvas page format (19 Nov 2026).
   Renders <x-dc> templates ({{expr}}, <sc-for>, <sc-if>, on* event bindings, ref) from the
   page's Component class (DCLogic: state, setState, renderVals, componentDidMount). */
(function () {
  var st = document.createElement('style');
  st.textContent = 'x-dc{display:none!important}';
  document.head.appendChild(st);

  function DCLogic(props) { this.props = props || {}; this.state = {}; }
  DCLogic.prototype.setState = function (part, cb) {
    var p = typeof part === 'function' ? part(this.state, this.props) : part;
    if (p) this.state = Object.assign({}, this.state, p);
    if (this.__schedule) this.__schedule();
    if (cb) Promise.resolve().then(cb);
  };
  DCLogic.prototype.forceUpdate = function () { if (this.__schedule) this.__schedule(); };
  DCLogic.prototype.renderVals = function () { return {}; };
  window.DCLogic = DCLogic;

  var RX = /\{\{([\s\S]*?)\}\}/g;
  function lookup(expr, scope) {
    var e = expr.trim();
    if (e === 'true') return true;
    if (e === 'false') return false;
    if (e === 'null') return null;
    if (/^-?\d+(\.\d+)?$/.test(e)) return Number(e);
    var parts = e.split('.'), v = scope[parts[0]];
    for (var i = 1; i < parts.length && v !== null && v !== undefined; i++) v = v[parts[i]];
    return v;
  }
  function single(s) { var m = /^\s*\{\{([\s\S]*?)\}\}\s*$/.exec(s); return m ? m[1] : null; }
  function interp(s, scope) {
    return s.replace(RX, function (_, e) { var v = lookup(e, scope); return v === null || v === undefined || v === false ? '' : String(v); });
  }

  // template DOM + scope -> list of virtual nodes
  function build(node, scope, out) {
    if (node.nodeType === 3) { out.push({ t: 'text', text: node.nodeValue.indexOf('{{') < 0 ? node.nodeValue : interp(node.nodeValue, scope) }); return; }
    if (node.nodeType !== 1) return;
    var tag = node.localName;
    if (tag === 'sc-for') {
      var list = lookup(single(node.getAttribute('list')) || '', scope) || [], as = node.getAttribute('as') || 'item';
      for (var i = 0; i < list.length; i++) {
        var s2 = Object.create(scope); s2[as] = list[i]; s2.$index = i;
        for (var c = node.firstChild; c; c = c.nextSibling) build(c, s2, out);
      }
      return;
    }
    if (tag === 'sc-if') {
      if (lookup(single(node.getAttribute('value')) || '', scope)) for (var c2 = node.firstChild; c2; c2 = c2.nextSibling) build(c2, scope, out);
      return;
    }
    var v = { t: 'el', tag: tag, ns: node.namespaceURI, attrs: {}, ev: {}, ref: null, kids: [] };
    for (var a = 0; a < node.attributes.length; a++) {
      var at = node.attributes[a], name = at.name, val = at.value;
      if (name.indexOf('hint-') === 0) continue;
      var e1 = single(val);
      if (name === 'ref') { v.ref = e1 ? lookup(e1, scope) : null; continue; }
      if (/^on[a-z]+$/.test(name) && e1 !== null) { var fn = lookup(e1, scope); if (typeof fn === 'function') v.ev[name.slice(2)] = fn; continue; }
      if (e1 !== null) {
        var x = lookup(e1, scope);
        if (x === false || x === null || x === undefined) { if (name.indexOf('aria-') === 0 && x === false) v.attrs[name] = 'false'; continue; }
        v.attrs[name] = String(x);
      } else v.attrs[name] = val.indexOf('{{') < 0 ? val : interp(val, scope);
    }
    var kids = tag === 'template' ? node.content : node;
    for (var k = kids.firstChild; k; k = k.nextSibling) build(k, scope, v.kids);
    out.push(v);
  }

  function setHandlers(el, ev) {
    var h = el.__h || (el.__h = {});
    Object.keys(h).forEach(function (k) { if (!ev[k]) h[k] = null; });
    Object.keys(ev).forEach(function (k) {
      if (!(k in h)) el.addEventListener(k, function (e) { var f = el.__h[k]; if (f) f(e); }, k === 'wheel' ? { passive: true } : false);
      h[k] = ev[k];
    });
  }
  function create(v) {
    if (v.t === 'text') return document.createTextNode(v.text);
    var el = v.ns && v.ns !== 'http://www.w3.org/1999/xhtml' ? document.createElementNS(v.ns, v.tag) : document.createElement(v.tag);
    Object.keys(v.attrs).forEach(function (k) { setAttr(el, k, v.attrs[k]); });
    setHandlers(el, v.ev);
    v.kids.forEach(function (c) { el.appendChild(create(c)); });
    el.__v = v;
    if (v.ref) { el.__ref = v.ref; v.ref(el); }
    return el;
  }
  function setAttr(el, k, val) {
    if (k === 'value' && 'value' in el && el.localName !== 'button') { if (el.value !== val) el.value = val; return; }
    if (k === 'checked' && 'checked' in el) { el.checked = val !== 'false'; return; }
    try { el.setAttribute(k, val); } catch (e) {}
  }
  function patchEl(el, o, n) {
    Object.keys(o.attrs).forEach(function (k) { if (!(k in n.attrs)) { if (k === 'value' && 'value' in el) el.value = ''; el.removeAttribute(k); } });
    Object.keys(n.attrs).forEach(function (k) { if (o.attrs[k] !== n.attrs[k] || k === 'value') setAttr(el, k, n.attrs[k]); });
    setHandlers(el, n.ev);
    if (n.ref !== el.__ref) { if (el.__ref) el.__ref(null); el.__ref = n.ref; if (n.ref) n.ref(el); }
    patchKids(el, o.kids, n.kids);
    el.__v = n;
  }
  function unref(el) {
    if (el.nodeType !== 1) return;
    if (el.__ref) { var r = el.__ref; el.__ref = null; r(null); }
    for (var c = el.firstChild; c; c = c.nextSibling) unref(c);
  }
  function patchKids(parent, oldK, newK) {
    var nodes = Array.prototype.slice.call(parent.childNodes);
    for (var i = 0; i < newK.length; i++) {
      var o = oldK[i], n = newK[i], el = nodes[i];
      if (!o || !el) { parent.appendChild(create(n)); continue; }
      if (o.t === 'text' && n.t === 'text') { if (o.text !== n.text) el.nodeValue = n.text; continue; }
      if (o.t === 'el' && n.t === 'el' && o.tag === n.tag && o.ns === n.ns) { patchEl(el, o, n); continue; }
      var fresh = create(n); unref(el); parent.replaceChild(fresh, el);
    }
    for (var j = nodes.length - 1; j >= newK.length; j--) { if (nodes[j].parentNode === parent) { unref(nodes[j]); parent.removeChild(nodes[j]); } }
  }

  function boot() {
    var host = document.querySelector('x-dc');
    if (!host) return;
    var tpl = document.createElement('template');
    tpl.innerHTML = host.innerHTML;
    host.parentNode.removeChild(host);
    var helmet = tpl.content.querySelector('helmet');
    if (helmet) { while (helmet.firstChild) document.head.appendChild(helmet.firstChild); helmet.parentNode.removeChild(helmet); }
    var sc = document.querySelector('script[data-dc-script]');
    var props = {};
    try { props = JSON.parse(sc.getAttribute('data-props') || '{}'); delete props.$preview; } catch (e) {}
    var Comp = DCLogic;
    if (sc) Comp = new Function('DCLogic', sc.textContent + '\n;return typeof Component !== "undefined" ? Component : DCLogic;')(DCLogic);
    var comp = new Comp(props), root = document.createElement('div');
    root.className = 'dc-root';
    document.body.insertBefore(root, document.body.firstChild);
    var cur = [], pending = false;
    function render() {
      pending = false;
      var vals = comp.renderVals() || {}, next = [];
      for (var c = tpl.content.firstChild; c; c = c.nextSibling) build(c, vals, next);
      patchKids(root, cur, next);
      cur = next;
    }
    comp.__schedule = function () { if (!pending) { pending = true; Promise.resolve().then(render); } };
    render();
    if (comp.componentDidMount) comp.componentDidMount();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
