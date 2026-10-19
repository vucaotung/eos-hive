(()=>{
"use strict";
const ST={backlog:["Tồn đọng","todo"],todo:["Chờ làm","todo"],in_progress:["Đang làm","prog"],blocked:["Vướng","wait"],in_review:["Chờ duyệt","review"],done:["Xong","done"],cancelled:["Đã hủy","todo"]};
const KIND={NHAN:"Nhận việc",HOI:"Hỏi","TRA-LOI":"Trả lời","KET-QUA":"Kết quả",LOI:"Lỗi","GHI-CHU":"Ghi chú",DUYET:"Đã duyệt","TU-CHOI":"Trả lại"};
const ROLE={"tra-cuu":"Tra cứu","phap-che":"Pháp chế","tai-chinh":"Tài chính","soan-thao":"Soạn thảo","kiem-tra":"Kiểm tra","lap-ke-hoach":"Lập kế hoạch"};
const PRI={urgent:"Gấp",high:"Cao",medium:"Thường",low:"Thấp"},PRI_ORD={urgent:0,high:1,medium:2,low:3};
const WD=["Chủ nhật","Thứ hai","Thứ ba","Thứ tư","Thứ năm","Thứ sáu","Thứ bảy"];

const $=s=>document.querySelector(s);
const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const store={get(k){try{return localStorage.getItem(k)}catch(e){return null}},set(k,v){try{v==null?localStorage.removeItem(k):localStorage.setItem(k,v)}catch(e){}}};
const today=()=>{const d=new Date();d.setHours(0,0,0,0);return d};
const pdate=s=>{if(!s)return null;const[y,m,d]=s.slice(0,10).split("-").map(Number);return new Date(y,m-1,d)};
const dd=d=>String(d.getDate()).padStart(2,"0")+"/"+String(d.getMonth()+1).padStart(2,"0");
const ddy=d=>dd(d)+"/"+d.getFullYear();
const roleName=r=>(ROLE[r]||r).toLowerCase();
function due(t){
  if(!t.due_date)return null;
  const d=pdate(t.due_date),n=Math.round((d-today())/864e5),closed=t.status==="done"||t.status==="cancelled";
  let txt="Hạn "+dd(d),cls="";
  if(!closed){if(n<0){txt="Quá hạn "+(-n)+" ngày";cls="late"}else if(n===0){txt="Hạn hôm nay";cls="soon"}else if(n===1){txt="Hạn ngày mai";cls="soon"}else if(n<=3){txt="Còn "+n+" ngày";cls="soon"}}
  return{txt,cls,n,closed};
}
function ago(iso){const s=(Date.now()-new Date(iso))/1e3;if(s<60)return"vừa xong";if(s<3600)return Math.floor(s/60)+" phút trước";if(s<86400)return Math.floor(s/3600)+" giờ trước";const d=Math.floor(s/86400);return d===1?"hôm qua":d+" ngày trước"}
function who(a){
  if(!a)return"";
  if(a.startsWith("agent:"))return"Agent "+roleName(a.slice(6));
  if(a.startsWith("human:")){const p=S.people.get(Number(a.slice(6)));return p?p.display_name:"Người dùng"}
  if(a.startsWith("hermes:"))return"Hermes "+a.slice(7);
  return a;
}
function toast(msg,bad){const t=$("#toast");t.textContent=msg;t.classList.toggle("bad",!!bad);t.classList.add("show");clearTimeout(t._h);t._h=setTimeout(()=>t.classList.remove("show"),2800)}
function jwtPayload(tok){try{return JSON.parse(decodeURIComponent(escape(atob(tok.split(".")[1].replace(/-/g,"+").replace(/_/g,"/")))))}catch(e){return null}}
const st=t=>{const[l,c]=ST[t.status]||ST.todo;return t.waiting_on_human&&t.status!=="done"?`<span class="st wait"><i></i>Chờ người trả lời</span>`:`<span class="st ${c}"><i></i>${l}</span>`};

const S={tab:"today",filter:"open",project:"all",mine:false,tasks:[],projects:[],people:new Map(),feed:[],results:new Map(),asks:new Map(),me:null,mode:"demo",err:null,loaded:false,arm:new Set()};

/* ---------- dữ liệu mẫu ---------- */
function demoData(){
  const D=n=>{const d=today();d.setDate(d.getDate()+n);return d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0")};
  const H=h=>new Date(Date.now()-h*36e5).toISOString();
  const people=[{id:1,display_name:"Tùng",team:"tung"},{id:2,display_name:"Minh",team:"tung"},{id:3,display_name:"Hà",team:"valnex"},{id:4,display_name:"Quân",team:"valnex"}];
  const projects=[{id:1,slug:"kdc-thanh-lap",name:"KDC Thành Lập",team:"tung"},{id:2,slug:"phu-dong-central-home",name:"Phù Đổng Central Home",team:"tung"},{id:3,slug:"thanh-my-loi-14-3ha",name:"Thạnh Mỹ Lợi 14,3 ha",team:"tung"},{id:4,slug:"biet-thu-dai-bai",name:"Biệt thự Đại Bái",team:"valnex"},{id:5,slug:"vistar-hoai-duc",name:"VISTAR Hoài Đức",team:"tung"}];
  const T=(id,project_id,title,status,o={})=>Object.assign({id,project_id,parent_id:null,title,description:null,status,priority:"medium",agent_role:null,waiting_on_human:false,approval_level:1,assignee_id:1,due_date:null,claimed_by:null,attempts:0,created_at:H(72),updated_at:H(5)},o);
  const tasks=[
    T(15,1,"Tra cứu ngày cấp GCN đầu tư, đối chiếu với KL 21","in_review",{agent_role:"tra-cuu",approval_level:2,due_date:D(1),priority:"high",claimed_by:"hermes:ops-admin",updated_at:H(1.2),description:"Câu hỏi: ngày cấp GCN đầu tư KDC Thành Lập.\nNguồn cần đối chiếu: KL 21, văn bản A.2.\nTrả về: kết luận, nguồn (văn bản, trang), trạng thái fact."}),
    T(16,1,"Chuẩn bị hồ sơ xin gia hạn tiến độ KDC Thành Lập","in_progress",{assignee_id:2,due_date:D(2),priority:"urgent",updated_at:H(3),description:"Mục tiêu: nộp hồ sơ xin gia hạn tiến độ trước hạn.\nNgười phụ trách: Minh.\nGồm 2 việc con: công văn nháp, bảng tổng hợp kinh phí bồi thường."}),
    T(17,1,"Soạn công văn xin gia hạn tiến độ (bản nháp)","in_review",{parent_id:16,agent_role:"soan-thao",approval_level:3,due_date:D(2),priority:"high",claimed_by:"hermes:ops-admin",updated_at:H(.4)}),
    T(18,1,"Tổng hợp kinh phí bồi thường đã chi trả theo từng đợt","blocked",{parent_id:16,agent_role:"tai-chinh",waiting_on_human:true,approval_level:2,due_date:D(3),priority:"high",claimed_by:"hermes:ops-admin",updated_at:H(2)}),
    T(19,2,"Đối chiếu diện tích chuyển đổi mục đích sử dụng đất","blocked",{agent_role:"phap-che",waiting_on_human:true,approval_level:2,due_date:D(-1),priority:"high",claimed_by:"hermes:ops-admin",updated_at:H(20)}),
    T(20,3,"Rà soát điều khoản góp vốn trong MOU hợp tác","todo",{agent_role:"phap-che",approval_level:2,due_date:D(5),updated_at:H(26)}),
    T(21,3,"Lập danh mục hồ sơ pháp lý bên chuyển nhượng cần cung cấp","in_progress",{agent_role:"lap-ke-hoach",due_date:D(4),claimed_by:"hermes:ops-admin",updated_at:H(.8)}),
    T(22,4,"Cập nhật tiến độ thi công phần thô tuần 42","todo",{assignee_id:3,due_date:D(1),updated_at:H(30)}),
    T(23,4,"Nghiệm thu cốp pha sàn tầng 2","in_progress",{assignee_id:4,due_date:D(0),priority:"high",updated_at:H(6)}),
    T(24,5,"Cập nhật kịch bản hợp nhất trong bảng tính khả thi","backlog",{assignee_id:2,priority:"low",updated_at:H(120)}),
    T(25,1,"Duyệt fact kdc-thanh-lap (69 fact)","done",{due_date:D(-2),updated_at:H(28),approval_level:2}),
    T(26,2,"Kiểm tra trích dẫn trong báo cáo pháp lý tháng 10","done",{agent_role:"kiem-tra",due_date:D(-1),updated_at:H(22)})];
  let cid=1;const C=(task_id,actor,kind,body,h)=>({id:cid++,task_id,actor,kind,body,created_at:H(h)});
  const comments=[
    C(15,"agent:tra-cuu","NHAN","Đã nhận việc",3),
    C(15,"agent:tra-cuu","KET-QUA","Ngày cấp GCN đầu tư là 05/01/2012, theo KL 21 trang 3.\nVăn bản A.2 ghi 05/01/2013 do lỗi OCR; fact này đã bị loại.\nFact dau_tu.gcn_ngay đã được người xác minh.",1.2),
    C(17,"agent:soan-thao","NHAN","Đã nhận việc",2.5),
    C(17,"agent:soan-thao","KET-QUA","Bản nháp công văn 2 trang gửi UBND tỉnh, kèm bảng tiến độ thực hiện đến nay.\nCăn cứ pháp lý do agent Pháp chế đề xuất nằm ở cuối bản nháp, anh kiểm tra trước khi ký.\nTệp: DEO-OS/kdc-thanh-lap/nhap/cv-gia-han-tien-do.md",.4),
    C(18,"agent:tai-chinh","NHAN","Đã nhận việc",4),
    C(18,"agent:tai-chinh","HOI","Bảng kê bồi thường đợt 3 có hai bản, ngày 14/06 và 02/07, tổng tiền khác nhau. Anh cho biết dùng bản nào?",2),
    C(19,"agent:phap-che","NHAN","Đã nhận việc",26),
    C(19,"agent:phap-che","HOI","Diện tích chuyển đổi trong quyết định giao đất khác với số trên bản đồ địa chính kèm theo. Anh xác nhận lấy theo văn bản nào?",20),
    C(21,"agent:lap-ke-hoach","NHAN","Đã nhận việc",.8),
    C(25,"human:1","DUYET","Đã duyệt",28),
    C(26,"agent:kiem-tra","KET-QUA","Đạt. 14/14 trích dẫn khớp nguồn.",22.5),
    C(16,"human:2","GHI-CHU","Đã xin lịch làm việc với Sở Kế hoạch và Đầu tư, chờ xác nhận.",3)];
  return{people,projects,tasks,comments};
}
let DEMO=null;

/* ---------- dữ liệu ---------- */
const cfg={get base(){return store.get("deo.base")||"/api"},get token(){return store.get("deo.token")||""}};
async function api(path,opt={}){
  const ctl=new AbortController(),tm=setTimeout(()=>ctl.abort(),15000);
  try{
    const r=await fetch(cfg.base.replace(/\/$/,"")+path,{method:opt.method||"GET",signal:ctl.signal,headers:{Authorization:"Bearer "+cfg.token,Accept:"application/json","Content-Type":"application/json"},body:opt.body?JSON.stringify(opt.body):undefined});
    const txt=await r.text();let j=null;try{j=txt?JSON.parse(txt):null}catch(e){}
    if(!r.ok){const e=new Error((j&&(j.message||j.hint))||("Máy chủ trả lỗi "+r.status));e.status=r.status;throw e}
    return j;
  }finally{clearTimeout(tm)}
}
const SEL="id,task_id,actor,kind,body,created_at";
const Data={
  async load(){
    if(S.mode==="demo"){if(!DEMO)DEMO=demoData();const c=DEMO.comments;
      return{people:DEMO.people,projects:DEMO.projects,tasks:DEMO.tasks.filter(t=>t.status!=="cancelled"),feed:[...c].sort((a,b)=>b.created_at.localeCompare(a.created_at)).slice(0,12),pick:c.filter(x=>x.kind==="KET-QUA"||x.kind==="HOI")}}
    const[people,projects,tasks,feed]=await Promise.all([
      api("/people?select=id,display_name,team"),
      api("/projects?select=id,slug,name,team,status&status=neq.closed&order=name"),
      api("/tasks?select=id,project_id,parent_id,title,description,status,priority,agent_role,waiting_on_human,approval_level,assignee_id,due_date,claimed_by,attempts,created_at,updated_at&status=neq.cancelled&order=updated_at.desc&limit=400"),
      api("/comments?select="+SEL+"&order=created_at.desc&limit=12")]);
    const ids=tasks.filter(t=>t.status==="in_review"||t.waiting_on_human).map(t=>t.id);
    const pick=ids.length?await api("/comments?select="+SEL+"&kind=in.(KET-QUA,HOI)&task_id=in.("+ids.join(",")+")&order=created_at.desc"):[];
    return{people,projects,tasks,feed,pick};
  },
  async comments(id){
    if(S.mode==="demo")return DEMO.comments.filter(c=>c.task_id===id).sort((a,b)=>a.created_at.localeCompare(b.created_at));
    return api("/comments?select="+SEL+"&task_id=eq."+id+"&order=created_at");
  },
  async approve(id,confirm){
    if(S.mode==="demo"){const t=DEMO.tasks.find(x=>x.id===id);if(t.approval_level===3&&!confirm)throw new Error("CAN_XAC_NHAN");t.status="done";t.updated_at=new Date().toISOString();dc(id,"DUYET","Đã duyệt");return t}
    return api("/rpc/app_approve",{method:"POST",body:{p_task:id,p_confirm:!!confirm}});
  },
  async reject(id,reason){
    if(S.mode==="demo"){const t=DEMO.tasks.find(x=>x.id===id);t.attempts++;if(t.attempts>=2){t.status="blocked";t.waiting_on_human=true}else t.status="todo";t.updated_at=new Date().toISOString();dc(id,"TU-CHOI",reason);return t}
    return api("/rpc/app_reject",{method:"POST",body:{p_task:id,p_reason:reason}});
  },
  async answer(id,text){
    if(S.mode==="demo"){const t=DEMO.tasks.find(x=>x.id===id);t.status="todo";t.waiting_on_human=false;t.updated_at=new Date().toISOString();dc(id,"TRA-LOI",text);return t}
    return api("/rpc/app_answer",{method:"POST",body:{p_task:id,p_answer:text}});
  },
  async note(id,text){
    if(S.mode==="demo"){dc(id,"GHI-CHU",text);return}
    return api("/rpc/app_comment",{method:"POST",body:{p_task:id,p_body:text}});
  }
};
function dc(task_id,kind,body){DEMO.comments.push({id:Date.now(),task_id,actor:"human:1",kind,body,created_at:new Date().toISOString()})}

async function refresh(quiet){
  const b=$("#btn-refresh");b.classList.add("spin");b.setAttribute("aria-busy","true");
  try{
    const d=await Data.load();
    S.people=new Map(d.people.map(p=>[p.id,p]));S.projects=d.projects;S.tasks=d.tasks;S.feed=d.feed;
    S.results=new Map();S.asks=new Map();
    for(const c of [...d.pick].sort((a,b)=>b.created_at.localeCompare(a.created_at))){const m=c.kind==="HOI"?S.asks:S.results;if(!m.has(c.task_id))m.set(c.task_id,c)}
    S.err=null;S.loaded=true;
  }catch(e){
    S.err=e.status===401||e.status===403?"Mã truy cập đã hết hạn hoặc không đúng. Mở Kết nối để dán mã mới.":(e.name==="AbortError"||e instanceof TypeError)?"Không kết nối được máy chủ. Kiểm tra Tailscale đang bật trên điện thoại rồi thử lại.":e.message;
    if(!quiet&&S.loaded)toast(S.err,true);
  }finally{b.classList.remove("spin");b.removeAttribute("aria-busy");conn();render()}
}
function conn(){const c=$("#conn");if(S.mode==="demo"){c.textContent="Dữ liệu mẫu";c.className="conn"}else if(S.err){c.textContent="Mất kết nối";c.className="conn off"}else{c.textContent=S.me&&S.me.name?S.me.name:"Đã kết nối";c.className="conn live"}}

/* ---------- truy vấn ---------- */
const proj=id=>S.projects.find(p=>p.id===id)||{name:"Không rõ dự án",slug:""};
const open=t=>t.status!=="done"&&t.status!=="cancelled";
const mine=t=>!S.me||!S.me.pid||t.assignee_id===S.me.pid;
const qReview=()=>S.tasks.filter(t=>t.status==="in_review").sort((a,b)=>b.approval_level-a.approval_level||a.updated_at.localeCompare(b.updated_at));
const qAsk=()=>S.tasks.filter(t=>t.waiting_on_human&&open(t)).sort((a,b)=>(a.due_date||"9").localeCompare(b.due_date||"9"));
const qLate=()=>S.tasks.filter(t=>{const d=due(t);return d&&!d.closed&&d.n<0});
const qRun=()=>S.tasks.filter(t=>t.status==="in_progress"&&t.agent_role);
const byPri=a=>a.sort((x,y)=>(PRI_ORD[x.priority]-PRI_ORD[y.priority])||(x.due_date||"9").localeCompare(y.due_date||"9"));

/* ---------- mảnh giao diện ---------- */
const chev=`<svg class="chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>`;
function row(t,o={}){
  const d=due(t),a=S.people.get(t.assignee_id);
  return `<button type="button" class="row" data-open="${t.id}"><span class="b">
    <span class="t">${esc(t.title)}</span>
    <span class="meta">${st(t)}${t.agent_role?`<span>Agent ${esc(roleName(t.agent_role))}</span>`:""}${o.noProject?"":`<span>${esc(proj(t.project_id).name)}</span>`}${a?`<span>${esc(a.display_name)}</span>`:""}${d?`<span class="${d.cls}">${d.txt}</span>`:""}<span>T-${t.id}</span></span>
  </span>${chev}</button>`;
}
const stack=(arr,empty,o)=>arr.length?`<div class="stack">${arr.map(t=>row(t,o)).join("")}</div>`:`<p class="none">${empty}</p>`;
function sealHTML(date,cls=""){return `<div class="seal ${cls}" aria-hidden="true">ĐÃ DUYỆT<small>${date?ddy(date):""}</small></div>`}
function slip(t){
  const res=S.results.get(t.id),arm=S.arm.has(t.id),p=proj(t.project_id);
  return `<article class="slip" data-slip="${t.id}" aria-labelledby="slip-${t.id}">
    <div class="who"><b>${esc(p.name)}</b>${t.agent_role?`<span>Agent ${esc(roleName(t.agent_role))}</span>`:""}<span>Cấp L${t.approval_level}</span><span>T-${t.id}</span>${t.attempts?`<span>Nộp lần ${t.attempts+1}</span>`:""}</div>
    <h3 id="slip-${t.id}"><button type="button" data-open="${t.id}">${esc(t.title)}</button></h3>
    ${res?`<div class="doc"><span class="by">${esc(who(res.actor))} nộp ${ago(res.created_at)}</span>${esc(res.body)}</div>`:`<div class="doc"><span class="by">Chưa có kết quả đính kèm</span>Mở việc để xem toàn bộ trao đổi.</div>`}
    ${t.approval_level===3?`<p class="lvl3">${arm?"Chạm lần nữa để đóng dấu. Việc cấp L3 cần xác nhận hai lần.":"Việc cấp L3: cần xác nhận hai lần."}</p>`:""}
    <div class="rej" hidden><label class="field" for="rej-${t.id}">Lý do trả lại<span class="hint">Agent sẽ làm lại theo góp ý này.</span><textarea id="rej-${t.id}" rows="2"></textarea></label></div>
    <div class="acts">
      <button type="button" class="btn quiet" data-reject="${t.id}">Trả lại</button>
      <button type="button" class="btn stamp${arm?" arm":""}" data-approve="${t.id}">${arm?"Xác nhận đóng dấu":"Đóng dấu duyệt"}</button>
    </div>
  </article>`;
}
function ask(t){
  const q=S.asks.get(t.id),p=proj(t.project_id),d=due(t);
  return `<article class="ask" aria-labelledby="ask-${t.id}">
    <p class="q" id="ask-${t.id}">${q?esc(q.body):"Agent đang chờ anh trả lời."}</p>
    <div class="ref"><button type="button" data-open="${t.id}">${esc(t.title)}</button><span>${esc(p.name)}</span>${q?`<span>${esc(who(q.actor))}, ${ago(q.created_at)}</span>`:""}${d&&d.cls?`<span class="${d.cls}">${d.txt}</span>`:""}</div>
    <label class="field" for="ans-${t.id}"><span class="sr">Trả lời cho T-${t.id}</span><textarea id="ans-${t.id}" rows="2" placeholder="Viết câu trả lời"></textarea></label>
    <div class="acts"><button type="button" class="btn pen" data-answer="${t.id}">Gửi trả lời</button></div>
  </article>`;
}
function loadingHTML(){return `<div class="hd"><p class="date">Đang tải việc</p></div><div class="stack" aria-busy="true" aria-label="Đang tải việc"><div class="ske"></div><div class="ske"></div><div class="ske"></div></div>`}
function errHTML(){return S.err?`<div class="err" role="alert"><p>${esc(S.err)}</p><div class="acts"><button type="button" class="btn quiet" data-retry>Thử lại</button><button type="button" class="btn quiet" data-settings>Mở kết nối</button></div></div>`:""}
const demoHTML=()=>S.mode==="demo"?`<p class="demo">Anh đang xem dữ liệu mẫu. <button type="button" data-settings>Kết nối hệ thống thật</button></p>`:"";

/* ---------- màn hình ---------- */
function vToday(){
  const r=qReview(),q=qAsk(),late=qLate(),run=qRun(),d=new Date();
  const parts=[];if(r.length)parts.push(r.length+" việc chờ duyệt");if(q.length)parts.push(q.length+" câu hỏi của agent");
  const lead=parts.length?"Anh có "+parts.join(" và ")+".":"Không có việc nào chờ anh.";
  const cnt=(n,l,go)=>`<button type="button" class="count${n?"":" zero"}" data-go="${go}"><b>${n}</b><span>${l}</span></button>`;
  const lateOnly=late.filter(t=>!t.waiting_on_human&&t.status!=="in_review");
  return `<div class="hd"><p class="date">${WD[d.getDay()]}, ${ddy(d)}</p><h1 class="lead${parts.length?"":" calm"}">${lead}</h1></div>
  ${errHTML()}${demoHTML()}
  <div class="counts" role="group" aria-label="Tổng quan, chạm để lọc">${cnt(r.length,"chờ duyệt","review")}${cnt(q.length,"agent hỏi","ask")}${cnt(late.length,"quá hạn","late")}${cnt(run.length,"agent đang chạy","run")}</div>
  <div class="cols"><div class="col">
  ${r.length?`<section aria-labelledby="h-r"><div class="sh"><h2 id="h-r">Chờ anh duyệt<span class="n">${r.length}</span></h2>${r.length>2?`<button type="button" data-tab="review">Xem cả ${r.length}</button>`:""}</div>${r.slice(0,2).map(slip).join("")}</section>`:`<section aria-labelledby="h-r"><div class="sh"><h2 id="h-r">Chờ anh duyệt</h2></div><p class="none">Không có việc nào chờ duyệt.</p></section>`}
  </div><div class="col">
  ${q.length?`<section aria-labelledby="h-q"><div class="sh"><h2 id="h-q">Agent đang hỏi<span class="n">${q.length}</span></h2></div>${q.map(ask).join("")}</section>`:""}
  ${lateOnly.length?`<section aria-labelledby="h-l"><div class="sh"><h2 id="h-l">Quá hạn</h2></div>${stack(lateOnly)}</section>`:""}
  <section aria-labelledby="h-f"><div class="sh"><h2 id="h-f">Vừa diễn ra</h2></div>
  ${S.feed.length?`<div class="stack feed">${S.feed.map(c=>{const t=S.tasks.find(x=>x.id===c.task_id);return `<button type="button" class="row" data-open="${c.task_id}"><span class="k ${esc(c.kind)}">${KIND[c.kind]||esc(c.kind)}</span><span class="b"><span class="t">${t?esc(t.title):"T-"+c.task_id}</span><span class="clamp">${esc(c.body)}</span><span class="meta"><span>${esc(who(c.actor))}</span><span>${ago(c.created_at)}</span></span></span></button>`}).join("")}</div>`:`<p class="none">Chưa có hoạt động nào.</p>`}
  </section></div></div>`;
}
const FILTERS=[["open","Đang mở",t=>open(t)&&t.status!=="backlog"],["ask","Chờ người",t=>t.waiting_on_human&&open(t)],["review","Chờ duyệt",t=>t.status==="in_review"],["late","Quá hạn",t=>{const d=due(t);return d&&!d.closed&&d.n<0}],["run","Agent đang chạy",t=>t.status==="in_progress"&&!!t.agent_role],["backlog","Tồn đọng",t=>t.status==="backlog"],["done","Xong",t=>t.status==="done"]];
function vTasks(){
  const base=S.tasks.filter(t=>S.project==="all"||t.project_id===Number(S.project)).filter(t=>!S.mine||mine(t));
  const f=FILTERS.find(x=>x[0]===S.filter)||FILTERS[0];
  let arr=base.filter(f[2]);arr=f[0]==="done"?arr.sort((a,b)=>b.updated_at.localeCompare(a.updated_at)):byPri(arr);
  const groups=S.project==="all"?S.projects.map(p=>[p,arr.filter(t=>t.project_id===p.id)]).filter(g=>g[1].length):[[proj(Number(S.project)),arr]];
  return `<div class="hd"><h1 class="title">Việc</h1><p class="sub">${S.tasks.filter(open).length} việc đang mở, ${S.projects.length} dự án</p></div>${errHTML()}
  <div class="filters">
    <div class="chips" role="group" aria-label="Lọc theo trạng thái">${FILTERS.map(([k,l,fn])=>`<button type="button" class="chip" data-filter="${k}" aria-pressed="${S.filter===k}">${l}<span class="c">${base.filter(fn).length}</span></button>`).join("")}</div>
    <div class="chips" role="group" aria-label="Lọc theo dự án"><button type="button" class="chip" data-mine aria-pressed="${S.mine}">Việc của tôi</button><button type="button" class="chip" data-project="all" aria-pressed="${S.project==="all"}">Mọi dự án</button>${S.projects.map(p=>`<button type="button" class="chip" data-project="${p.id}" aria-pressed="${String(p.id)===String(S.project)}">${esc(p.name)}</button>`).join("")}</div>
  </div>
  ${arr.length?groups.map(([p,ts])=>`<section aria-label="${esc(p.name)}"><p class="group">${esc(p.name)}</p>${stack(ts,"",{noProject:true})}</section>`).join(""):`<p class="none">Không có việc nào khớp bộ lọc này.</p>`}`;
}
function vReview(){
  const r=qReview();
  return `<div class="hd"><h1 class="title">Duyệt</h1><p class="sub">${r.length?r.length+" việc agent đã làm xong, chờ anh đóng dấu":"Không còn việc nào chờ duyệt"}</p></div>${errHTML()}
  ${r.length?`<div class="rgrid">${r.map(slip).join("")}</div>`:`<p class="none">Khi agent nộp kết quả cần duyệt, việc sẽ hiện ở đây.</p>`}`;
}
function vProjects(){
  const card=p=>{
    const ts=S.tasks.filter(t=>t.project_id===p.id),n=ts.length;
    const seg=[["done","xong",t=>t.status==="done"],["review","chờ duyệt",t=>t.status==="in_review"],["wait","vướng",t=>t.status==="blocked"],["prog","đang làm",t=>t.status==="in_progress"],["todo","chờ làm",t=>t.status==="todo"||t.status==="backlog"]].map(([c,l,f])=>[c,l,ts.filter(f).length]);
    const done=seg[0][2],late=ts.filter(t=>{const d=due(t);return d&&!d.closed&&d.n<0}).length;
    const says=seg.slice(1).filter(s=>s[2]).map(([,l,c])=>`<b>${c}</b> ${l}`).join(", ");
    return `<button type="button" class="proj" data-pgo="${p.id}">
      <span class="pl"><span class="pn">${esc(p.name)}</span><span class="pct">${done}<small>/ ${n} xong</small></span></span>
      <span class="bar" role="img" aria-label="${seg.map(s=>s[2]+" "+s[1]).join(", ")}">${seg.filter(s=>s[2]).map(([c,,k])=>`<span class="b-${c}" style="flex:${k}"></span>`).join("")}</span>
      <span class="says">${n?(says||"Mọi việc đã xong")+(late?`, <b class="late">${late} quá hạn</b>`:""):"Chưa có việc nào"}</span>
    </button>`;
  };
  const teams=[["tung","Team Tùng"],["valnex","Team Valnex"]];
  return `<div class="hd"><h1 class="title">Dự án</h1><p class="sub">${S.projects.length} dự án đang theo dõi</p></div>${errHTML()}
  ${teams.map(([k,l])=>{const ps=S.projects.filter(p=>p.team===k);return ps.length?`<section aria-labelledby="t-${k}"><div class="sh"><h2 id="t-${k}">${l}</h2></div><div class="stack pgrid">${ps.map(card).join("")}</div></section>`:""}).join("")}`;
}
function render(){
  const m=$("#main");
  if(!S.loaded&&!S.err){m.innerHTML=loadingHTML();return}
  if(!S.loaded&&S.err){m.innerHTML=`<div class="hd"><h1 class="title">Dẹo Việc</h1></div>${errHTML()}`;return}
  m.innerHTML={today:vToday,tasks:vTasks,review:vReview,projects:vProjects}[S.tab]();
  document.querySelectorAll("#tabs button").forEach(b=>b.dataset.tab===S.tab?b.setAttribute("aria-current","page"):b.removeAttribute("aria-current"));
  mark();
  const n=qReview().length,dot=$("#dot-review");dot.hidden=!n;dot.textContent=n;dot.setAttribute("aria-label",n+" việc chờ duyệt");
}
function go(tab){S.tab=tab;store.set("deo.tab",tab);render();window.scrollTo({top:0});$("#main").focus({preventScroll:true})}

/* ---------- bảng trượt: giữ tiêu điểm bên trong, trả lại khi đóng ---------- */
let lastFocus=null,openId=null;
const desk=matchMedia("(min-width:1024px)");
function mark(){document.querySelectorAll(".row.on").forEach(r=>r.classList.remove("on"));if(openId!=null)document.querySelectorAll(`#main .row[data-open="${openId}"]`).forEach(r=>r.classList.add("on"))}
function openSheet(html){
  const sc=$("#scrim"),sh=$("#sheet");
  if(sh.hidden)lastFocus=document.activeElement;
  $("#sbody").innerHTML=html;$("#sbody").scrollTop=0;sh.hidden=false;
  if(desk.matches){sh.setAttribute("aria-modal","false");document.body.classList.add("panel")}
  else{sh.setAttribute("aria-modal","true");sc.hidden=false;for(const el of [$("#main"),$("#top"),$(".tabbar")])el.inert=true;document.body.style.overflow="hidden"}
  requestAnimationFrame(()=>{sc.classList.add("open");sh.classList.add("open")});
  const h=sh.querySelector("#sheet-title");if(h){h.tabIndex=-1;h.focus({preventScroll:true})}
}
function closeSheet(){
  const sc=$("#scrim"),sh=$("#sheet");if(sh.hidden)return;
  sc.classList.remove("open");sh.classList.remove("open");sh.style.transform="";document.body.style.overflow="";document.body.classList.remove("panel");openId=null;mark();
  for(const el of [$("#main"),$("#top"),$(".tabbar")])el.inert=false;
  setTimeout(()=>{sc.hidden=true;sh.hidden=true},280);
  if(lastFocus&&document.contains(lastFocus))lastFocus.focus({preventScroll:true});
}
async function openTask(id){
  const t=S.tasks.find(x=>x.id===id);if(!t)return;openId=id;
  const d=due(t),p=proj(t.project_id),a=S.people.get(t.assignee_id),parent=t.parent_id&&S.tasks.find(x=>x.id===t.parent_id),subs=S.tasks.filter(x=>x.parent_id===t.id);
  openSheet(`<div class="meta">${st(t)}<span>Cấp L${t.approval_level}</span><span>T-${t.id}</span></div>
    <h2 class="st-title" id="sheet-title">${esc(t.title)}</h2>
    <div id="sealbox" hidden></div>
    <dl class="facts">
      <dt>Dự án</dt><dd>${esc(p.name)}</dd>
      <dt>Phụ trách</dt><dd>${a?esc(a.display_name):"Chưa giao"}</dd>
      ${t.agent_role?`<dt>Agent</dt><dd>${esc(ROLE[t.agent_role]||t.agent_role)}${t.claimed_by?`, chạy trên ${esc(t.claimed_by.replace("hermes:",""))}`:""}</dd>`:""}
      <dt>Ưu tiên</dt><dd>${PRI[t.priority]||t.priority}</dd>
      ${d?`<dt>Hạn</dt><dd class="${d.cls}">${ddy(pdate(t.due_date))}${d.cls?", "+d.txt.toLowerCase():""}</dd>`:""}
      ${parent?`<dt>Thuộc việc</dt><dd><button type="button" data-open="${parent.id}">${esc(parent.title)}</button></dd>`:""}
      <dt>Cập nhật</dt><dd>${ago(t.updated_at)}</dd>
    </dl>
    ${t.description?`<div class="desc">${esc(t.description)}</div>`:""}
    <div id="act"></div>
    ${subs.length?`<section aria-labelledby="h-sub"><div class="sh"><h2 id="h-sub">Việc con</h2></div>${stack(subs,"",{noProject:true})}</section>`:""}
    <section aria-labelledby="h-tl"><div class="sh"><h2 id="h-tl">Trao đổi</h2></div><div class="tl" id="tl" aria-busy="true"><div class="ske" style="height:56px"></div></div></section>`);
  mark();
  const act=$("#act");
  if(t.waiting_on_human&&open(t))act.innerHTML=ask(t);
  else if(t.status==="in_review")act.innerHTML=slip(t);
  else if(open(t))act.innerHTML=`<div class="ask"><label class="field" for="note">Thêm ghi chú<span class="hint">Ghi chú được lưu vào trao đổi của việc này.</span><textarea id="note" rows="2"></textarea></label><div class="acts"><button type="button" class="btn quiet" data-note="${t.id}">Lưu ghi chú</button></div></div>`;
  try{
    const cs=await Data.comments(id),tl=$("#tl");if(!tl)return;tl.removeAttribute("aria-busy");
    tl.innerHTML=cs.length?cs.map(c=>`<div class="ev"><div class="h"><span class="k ${esc(c.kind)}">${KIND[c.kind]||esc(c.kind)}</span><span>${esc(who(c.actor))}</span><span>${ago(c.created_at)}</span></div><div class="x">${esc(c.body)}</div></div>`).join(""):`<p class="none">Chưa có trao đổi.</p>`;
    const ok=[...cs].reverse().find(c=>c.kind==="DUYET"),box=$("#sealbox");
    if(t.status==="done"&&ok&&box){box.innerHTML=sealHTML(new Date(ok.created_at),"inline");box.hidden=false}
  }catch(e){const tl=$("#tl");if(tl)tl.innerHTML=`<div class="err" role="alert"><p>${esc(e.message)}</p></div>`}
}
function openSettings(){
  const tok=cfg.token,pl=tok?jwtPayload(tok):null,exp=pl&&pl.exp?new Date(pl.exp*1e3):null,expired=exp&&exp<new Date();
  openSheet(`<h2 class="st-title" id="sheet-title">Kết nối</h2>
    <p class="sub" style="margin:0">App đọc và ghi vào hệ thống công việc qua mạng Tailscale. Điện thoại cần bật Tailscale.</p>
    ${pl?`<dl class="facts"><dt>Đăng nhập</dt><dd>${esc(pl.name||pl.sub||"Không rõ")}</dd>${exp?`<dt>Mã hết hạn</dt><dd class="${expired?"late":""}">${ddy(exp)}${expired?", đã hết hạn":""}</dd>`:""}</dl>`:""}
    <label class="field" for="set-token">Mã truy cập<input id="set-token" type="password" value="${esc(tok)}" autocomplete="off" spellcheck="false" placeholder="Dán mã anh nhận được"><span class="hint">Mỗi người một mã riêng. Không gửi mã qua chat với bot.</span></label>
    <label class="field" for="set-base">Địa chỉ máy chủ<input id="set-base" type="url" value="${esc(cfg.base)}" autocomplete="off" spellcheck="false"><span class="hint">Để nguyên /api khi mở app từ chính máy chủ.</span></label>
    <div class="acts"><button type="button" class="btn quiet" id="set-demo">Xem dữ liệu mẫu</button><button type="button" class="btn pen" id="set-save">Lưu và kết nối</button></div>
    <label class="field" for="set-theme">Giao diện<select id="set-theme"><option value="">Theo điện thoại</option><option value="light">Sáng</option><option value="dark">Tối</option></select></label>`);
  $("#set-theme").value=store.get("deo.theme")||"";
}
function applyAuth(){const tok=cfg.token;if(tok){const pl=jwtPayload(tok);S.mode="live";S.me=pl?{pid:pl.pid?Number(pl.pid):null,name:pl.name||null}:null}else{S.mode="demo";S.me={pid:1,name:"Tùng"}}}
function applyTheme(){const t=store.get("deo.theme");t?document.documentElement.setAttribute("data-theme",t):document.documentElement.removeAttribute("data-theme")}

/* ---------- duyệt: con dấu in xuống ngay, gỡ ra nếu máy chủ từ chối ---------- */
async function approve(btn,id){
  const card=btn.closest(".slip"),arm=S.arm.has(id),t=S.tasks.find(x=>x.id===id);
  if(t.approval_level===3&&!arm){S.arm.add(id);redraw(id);const b=document.querySelector(`[data-slip="${id}"] [data-approve]`);if(b)b.focus();return}
  btn.disabled=true;card.insertAdjacentHTML("beforeend",sealHTML(new Date(),"press"));
  try{
    await Data.approve(id,arm);S.arm.delete(id);toast("Đã duyệt T-"+id);
    setTimeout(()=>{card.classList.add("gone");setTimeout(()=>{closeSheet();refresh(true)},320)},650);
  }catch(e){
    card.querySelector(".seal.press")?.remove();btn.disabled=false;
    if(/CAN_XAC_NHAN/.test(e.message)){S.arm.add(id);redraw(id)}else toast(e.message,true);
  }
}
function redraw(id){const t=S.tasks.find(x=>x.id===id);document.querySelectorAll(`[data-slip="${id}"]`).forEach(c=>{c.outerHTML=slip(t)})}

document.addEventListener("click",async e=>{
  const el=e.target.closest("button");if(!el)return;const ds=el.dataset;
  if(ds.tab){go(ds.tab);return}
  if(ds.go){if(ds.go==="review")go("review");else{S.filter=ds.go;S.project="all";go("tasks")}return}
  if(ds.pgo){S.project=ds.pgo;S.filter="open";go("tasks");return}
  if(ds.filter){S.filter=ds.filter;render();return}
  if(ds.project){S.project=ds.project;render();return}
  if("mine" in ds){S.mine=!S.mine;render();return}
  if(ds.open){openTask(Number(ds.open));return}
  if("retry" in ds||el.id==="btn-refresh"){refresh();return}
  if("settings" in ds||el.id==="btn-settings"){openSettings();return}
  if(el.id==="btn-close"){closeSheet();return}
  if(el.id==="set-save"){store.set("deo.token",$("#set-token").value.trim()||null);store.set("deo.base",$("#set-base").value.trim()||"/api");applyAuth();S.loaded=false;S.err=null;closeSheet();render();await refresh(true);if(!S.err&&S.mode==="live")toast("Đã kết nối");return}
  if(el.id==="set-demo"){store.set("deo.token",null);applyAuth();DEMO=null;S.loaded=false;S.err=null;closeSheet();refresh(true);toast("Đang xem dữ liệu mẫu");return}
  if(ds.approve){approve(el,Number(ds.approve));return}
  if(ds.reject){
    const id=Number(ds.reject),card=el.closest(".slip"),box=card.querySelector(".rej"),ta=box.querySelector("textarea");
    if(box.hidden){box.hidden=false;el.textContent="Gửi trả lại";ta.focus();return}
    const reason=ta.value.trim();if(!reason){toast("Ghi lý do để agent biết cần sửa gì",true);ta.focus();return}
    el.disabled=true;try{await Data.reject(id,reason);S.arm.delete(id);toast("Đã trả T-"+id+" về cho agent");card.classList.add("gone");setTimeout(()=>{closeSheet();refresh(true)},320)}catch(err){toast(err.message,true);el.disabled=false}
    return}
  if(ds.answer){
    const id=Number(ds.answer),ta=document.getElementById("ans-"+id),v=ta.value.trim();if(!v){toast("Viết câu trả lời trước khi gửi",true);ta.focus();return}
    el.disabled=true;try{await Data.answer(id,v);toast("Đã gửi, agent sẽ làm tiếp");el.closest(".ask").style.opacity=".4";setTimeout(()=>{closeSheet();refresh(true)},300)}catch(err){toast(err.message,true);el.disabled=false}
    return}
  if(ds.note){const id=Number(ds.note),v=$("#note").value.trim();if(!v){$("#note").focus();return}
    el.disabled=true;try{await Data.note(id,v);toast("Đã lưu ghi chú");openTask(id);refresh(true)}catch(err){toast(err.message,true);el.disabled=false}return}
});
document.addEventListener("change",e=>{if(e.target.id==="set-theme"){store.set("deo.theme",e.target.value||null);applyTheme()}});
$("#scrim").addEventListener("click",closeSheet);
document.addEventListener("keydown",e=>{
  const sh=$("#sheet");if(sh.hidden)return;
  if(e.key==="Escape"){closeSheet();return}
  if(e.key==="Tab"&&!desk.matches){const f=[...sh.querySelectorAll("button:not([disabled]),textarea,input,select")].filter(x=>x.offsetParent!==null);if(!f.length)return;
    const first=f[0],last=f[f.length-1],cur=document.activeElement;
    if(e.shiftKey&&(cur===first||!sh.contains(cur)||cur.id==="sheet-title")){e.preventDefault();last.focus()}else if(!e.shiftKey&&cur===last){e.preventDefault();first.focus()}}
});
(()=>{let y0=null,dy=0;const sh=$("#sheet"),body=$("#sbody");
  sh.addEventListener("touchstart",e=>{if(e.target.closest("textarea,input,select"))return;if(e.target.closest(".grab")||body.scrollTop<=0){y0=e.touches[0].clientY;dy=0;sh.style.transition="none"}},{passive:true});
  sh.addEventListener("touchmove",e=>{if(y0==null)return;dy=Math.max(0,e.touches[0].clientY-y0);if(dy>0)sh.style.transform=`translateY(${dy}px)`},{passive:true});
  sh.addEventListener("touchend",()=>{if(y0==null)return;sh.style.transition="";if(dy>110)closeSheet();else sh.style.transform="";y0=null});
})();
desk.addEventListener("change",()=>closeSheet());
let ticking=false;addEventListener("scroll",()=>{if(ticking)return;ticking=true;requestAnimationFrame(()=>{$("#top").classList.toggle("scrolled",scrollY>4);ticking=false})},{passive:true});
document.addEventListener("visibilitychange",()=>{if(!document.hidden&&S.mode==="live")refresh(true)});
setInterval(()=>{if(!document.hidden&&S.mode==="live"&&($("#sheet").hidden||desk.matches))refresh(true)},60000);

(function boot(){
  const m=location.hash.match(/^#t=([\w-]+\.[\w-]+\.[\w-]+)$/);
  if(m){store.set("deo.token",m[1]);try{history.replaceState(null,"",location.pathname+location.search)}catch(e){}}
  applyTheme();applyAuth();
  const t=store.get("deo.tab");S.tab=["today","tasks","review","projects"].includes(t)?t:"today";
  conn();render();refresh(true);
})();
})();
