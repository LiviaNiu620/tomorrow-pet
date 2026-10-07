'use strict';
const { randomUUID } = require('node:crypto');
const active = t => !['completed','cancelled','archived','trashed'].includes(t.status);
function dayKey(value = new Date()) { if(typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value))return value; const d = new Date(value); if (!Number.isFinite(d.getTime())) throw new Error('日期无效'); return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`; }
function localDay(s) { const d = new Date(`${s}T00:00:00`); if (dayKey(d) !== s) throw new Error('日期无效'); return d; }
function shiftDay(s, n) { const d = localDay(s); d.setDate(d.getDate()+n); return dayKey(d); }
function weekKey(s) { const d=localDay(s); d.setDate(d.getDate()-((d.getDay()+6)%7)); return dayKey(d); }
function text(v,max=10000) { if(typeof v !== 'string'||v.length>max) throw new Error('文字格式或长度无效'); return v.trim(); }
function integer(v,min,max) { if(!Number.isInteger(v)||v<min||v>max)throw new Error(`数值须介于 ${min}–${max}`); return v; }
const isoDay = v => v ? localDay(dayKey(v)).toISOString() : null;
const priorityRank = {high:0,medium:1,low:2,none:3};
function defaults() {
 return {schemaVersion:1,tasks:[],areas:['个人','工作','学习','健康','家庭','财务'].map((name,i)=>({id:randomUUID(),name,colorName:['teal','blue','purple','pink','orange','green'][i],systemImage:'circle'})),weeks:{},habits:structuredClone(require('./habits.json')),blocks:structuredClone(require('./blocks.json')),completions:{},reviews:{},sessions:[],events:[],undo:[],focus:null,settings:{model:'gpt-5.6',dailyTime:'21:30',weeklyTime:'20:30',reminders:true,pet:true},acceptedPlans:[]};
}
function parseCapture(value, state, now=new Date()) {
 let title=text(value,1000), date=null, minute=null, duration=null, priority='none', areaID=null;
 const today=dayKey(now);
 title=title.replace(/(今天|明天|后天)/,(_,s)=>{date=shiftDay(today,{'今天':0,'明天':1,'后天':2}[s]);return '';});
 title=title.replace(/(?:周|星期)([一二三四五六日天])/,(_,s)=>{const target='日一二三四五六'.indexOf(s==='天'?'日':s);date=shiftDay(today,(target-now.getDay()+7)%7);return '';});
 title=title.replace(/(上午|下午|晚上)?\s*(\d{1,2})(?::(\d{2})|点(?:(\d{1,2})分?)?)/,(_,period,h,m,m2)=>{let hour=Number(h);if(['下午','晚上'].includes(period)&&hour<12)hour+=12;minute=integer(hour,0,23)*60+integer(Number(m||m2||0),0,59);return '';});
 title=title.replace(/(?:^|\s)(\d+(?:\.\d+)?)\s*(m|min|分钟|h|小时)(?=\s|$)/i,(_,n,u)=>{duration=integer(Math.round(Number(n)*(/h|小时/i.test(u)?60:1)),5,480);return ' ';});
 title=title.replace(/[!！](高|中|低)/,(_,p)=>{priority={高:'high',中:'medium',低:'low'}[p];return '';});
 const tags=[];title=title.replace(/#([^\s#]+)/g,(_,tag)=>{const area=state.areas.find(a=>a.name===tag);if(area)areaID=area.id;else tags.push(tag);return '';});
 title=title.replace(/\s+/g,' ').trim();if(!title)throw new Error('请输入任务标题');
 return {title,areaID,priority,tags,plannedDate:date?isoDay(date):null,scheduledMinute:date?minute:null,estimatedMinutes:duration};
}
function newTask(values={}) {
 return {id:randomUUID(),title:'',notes:'',areaID:null,project:'',tags:[],status:'inbox',manualHorizon:null,priority:'none',estimatedMinutes:null,dueDate:null,plannedDate:null,focusDate:null,reviewDate:null,source:'manual',sourceEventID:null,createdAt:new Date().toISOString(),completedAt:null,recurrence:null,recurrenceSeriesID:null,parentTaskID:null,trashedFromStatus:null,deletedAt:null,scheduledMinute:null,weeklyGoalIndex:null,postponeCount:0,...values};
}
function validateTask(t) {
 t.title=text(t.title,1000); if(!t.title)throw new Error('任务标题不能为空'); t.notes=text(t.notes||'',30000);t.project=text(t.project||'',500);
 if(!Object.hasOwn(priorityRank,t.priority))throw new Error('优先级无效');
 if(!['inbox','next','planned','inProgress','waiting','completed','cancelled','archived','trashed'].includes(t.status))throw new Error('任务状态无效');
 for(const field of ['plannedDate','dueDate','focusDate','reviewDate'])if(t[field])t[field]=isoDay(t[field]);
 if(t.scheduledMinute!=null)integer(t.scheduledMinute,0,1439);if(t.estimatedMinutes!=null)integer(t.estimatedMinutes,5,480);
 if(t.weeklyGoalIndex!=null)integer(t.weeklyGoalIndex,0,2);
 if(!Array.isArray(t.tags)||t.tags.length>50)throw new Error('标签无效');t.tags=t.tags.map(x=>text(x,100));
 if(t.recurrence){integer(t.recurrence.interval,1,99);if(!['daily','weekly','monthly'].includes(t.recurrence.frequency))throw new Error('重复周期无效');if(t.recurrence.endDate)isoDay(t.recurrence.endDate);if(!Array.isArray(t.recurrence.weekdays))throw new Error('重复星期无效');t.recurrence.weekdays.forEach(x=>integer(x,1,7));}
 return t;
}
function nextDate(task) {
 const r=task.recurrence;if(!r)return null;let base=dayKey(task.plannedDate||task.dueDate||new Date()),d=localDay(base);
 if(r.frequency==='daily')d.setDate(d.getDate()+r.interval);
 else if(r.frequency==='monthly'){const day=d.getDate();d.setDate(1);d.setMonth(d.getMonth()+r.interval);const last=new Date(d.getFullYear(),d.getMonth()+1,0).getDate();d.setDate(Math.min(day,last));}
 else { const days=r.weekdays||[];if(!days.length)d.setDate(d.getDate()+r.interval*7);else {const start=localDay(weekKey(base));let found;for(let n=1;n<=r.interval*7+7;n++){const candidate=localDay(shiftDay(base,n));const weekDelta=Math.floor((Date.UTC(candidate.getFullYear(),candidate.getMonth(),candidate.getDate())-Date.UTC(start.getFullYear(),start.getMonth(),start.getDate()))/86400000/7);if((weekDelta===0||weekDelta===r.interval)&&days.includes(candidate.getDay()+1)){found=candidate;break;}}d=found;}}
 if(!d)return null;const next=dayKey(d);return r.endDate&&next>dayKey(r.endDate)?null:next;
}
function finishTask(state,t,completed) {
 const was=t.status==='completed';t.status=completed?'completed':'next';t.completedAt=completed?new Date().toISOString():null;
 if(completed&&!was&&t.recurrence){const next=nextDate(t);if(next){t.recurrenceSeriesID ||= t.id;const exists=state.tasks.some(x=>active(x)&&x.recurrenceSeriesID===t.recurrenceSeriesID&&dayKey(x.plannedDate||x.dueDate||new Date())===next);if(!exists){const base=dayKey(t.plannedDate||t.dueDate||t.completedAt), offset=Math.round((localDay(next)-localDay(base))/86400000);const shifted=field=>t[field]?isoDay(shiftDay(dayKey(t[field]),offset)):null;state.tasks.push(newTask({...t,id:randomUUID(),status:t.plannedDate?'planned':'next',completedAt:null,plannedDate:shifted('plannedDate'),dueDate:shifted('dueDate'),reviewDate:shifted('reviewDate'),focusDate:null,createdAt:new Date().toISOString(),sourceEventID:null}));}}}
}
function snapshot(s) { s.undo.push(structuredClone(s.tasks));if(s.undo.length>20)s.undo.shift(); }
function habitItems(s,date) { const d=localDay(date);return s.habits.filter(h=>h.scope==='everyday'||(d.getDay()===0&&(h.scope==='sunday'||new Date(d.getFullYear(),d.getMonth(),d.getDate()+7).getMonth()!==d.getMonth()))); }
function rangesFree(occupied,start=420,end=1440) {const ranges=occupied.filter(x=>x.end>x.start).sort((a,b)=>a.start-b.start);let cursor=start,result=[];for(const r of ranges){if(r.start>cursor)result.push({start:cursor,end:Math.min(end,r.start)});cursor=Math.max(cursor,r.end);if(cursor>=end)break;}if(cursor<end)result.push({start:cursor,end});return result.filter(r=>r.end>r.start);}
function placeTasks(durations,occupied) {const used=[...occupied];return durations.map(length=>{for(const free of rangesFree(used)){const start=Math.ceil(free.start/15)*15;if(start+length<=free.end){used.push({start,end:start+length});return start;}}return null;});}
function tickFocus(s,now=Date.now()) {const f=s.focus;if(!f||f.status!=='running'||now<f.endsAt)return false;s.sessions.push({id:randomUUID(),taskID:f.taskID,taskTitle:f.title,startedAt:new Date(f.startedAt).toISOString(),minutes:f.minutes});s.focus={...f,status:'finished',remainingMs:0};return true;}
function applyAction(s,action,p={},now=Date.now()) {
 const task=()=>{const t=s.tasks.find(x=>x.id===p.id);if(!t)throw new Error('任务不存在');return t;};
 switch(action){
 case 'addTask':{snapshot(s);const values=parseCapture(p.text,s,new Date(now));if(p.date&&!values.plannedDate)values.plannedDate=isoDay(p.date);s.tasks.push(newTask({...values,status:values.plannedDate?'planned':'inbox'}));break;}
 case 'updateTask': {const t=task();const patch={};for(const key of ['title','notes','areaID','project','tags','priority','estimatedMinutes','plannedDate','dueDate','reviewDate','scheduledMinute','weeklyGoalIndex','focusDate','recurrence','manualHorizon','status'])if(Object.hasOwn(p.patch||{},key))patch[key]=p.patch[key];const next=validateTask({...t,...patch});if(next.areaID&&!s.areas.some(a=>a.id===next.areaID))throw new Error('领域不存在');if(next.focusDate&&active(next)&&s.tasks.filter(x=>x.id!==t.id&&active(x)&&x.focusDate&&dayKey(x.focusDate)===dayKey(next.focusDate)).length>=3)throw new Error('每天最多三个重点，请先取消一个');if(!next.plannedDate)next.scheduledMinute=null;else if(next.status==='inbox')next.status='planned';snapshot(s);const targetStatus=next.status,completed=targetStatus==='completed';next.status=t.status;Object.assign(t,next);if(completed!==(t.status==='completed'))finishTask(s,t,completed);t.status=targetStatus;break;}
 case 'toggleTask':snapshot(s);finishTask(s,task(),task().status!=='completed');break;
 case 'trashTask':{const t=task();snapshot(s);t.trashedFromStatus=t.status;t.status='trashed';t.deletedAt=new Date(now).toISOString();break;}
 case 'restoreTask':{const t=task();snapshot(s);t.status=t.trashedFromStatus||'inbox';t.deletedAt=null;break;}
 case 'undo':if(s.undo.length)s.tasks=s.undo.pop();break;
 case 'week':{const k=weekKey(text(p.date,10));if(!Array.isArray(p.goals)||p.goals.length>3)throw new Error('最多三个目标');s.weeks[k]={goals:p.goals.map(x=>text(x,500)),notes:text(p.notes||''),updatedAt:new Date(now).toISOString()};break;}
 case 'toggleHabit':{localDay(p.date);if(!s.habits.some(x=>x.id===p.id))throw new Error('习惯不存在');const checked=new Set(s.completions[p.date]||[]);checked.has(p.id)?checked.delete(p.id):checked.add(p.id);s.completions[p.date]=[...checked];break;}
 case 'saveHabit':{const h={id:p.id||randomUUID(),title:text(p.title,300),time:p.time||'',sectionTitle:text(p.sectionTitle||'自定义',100),scope:p.scope||'everyday',isPlanningContext:p.isPlanningContext!==false};if(!h.title)throw new Error('习惯名称不能为空');if(!['everyday','sunday','monthEnd'].includes(h.scope))throw new Error('频率无效');if(h.time&&!/^([01]\d|2[0-3]):[0-5]\d$/.test(h.time))throw new Error('时间格式为 HH:mm');const i=s.habits.findIndex(x=>x.id===h.id);if(i>=0)s.habits[i]={...s.habits[i],...h};else s.habits.push(h);break;}
 case 'deleteHabit':s.habits=s.habits.filter(x=>x.id!==p.id);break;
 case 'review':{localDay(p.date);s.reviews[p.date]={progress:text(p.progress||''),blocker:text(p.blocker||''),firstAction:text(p.firstAction||''),energy:integer(Number(p.energy),1,5),mood:integer(Number(p.mood),1,5),savedAt:new Date(now).toISOString()};break;}
 case 'focusStart': {if(s.focus?.status==='paused'){s.focus.endsAt=now+s.focus.remainingMs;s.focus.status='running';}else{const minutes=integer(Number(p.minutes),1,180);const t=s.tasks.find(x=>x.id===p.taskID);s.focus={id:randomUUID(),status:'running',minutes,remainingMs:minutes*60000,endsAt:now+minutes*60000,startedAt:now,taskID:t?.id||null,title:t?.title||'自由专注'};}break;}
 case 'focusPause':if(s.focus?.status==='running'){if(!tickFocus(s,now)){s.focus.remainingMs=Math.max(0,s.focus.endsAt-now);s.focus.status='paused';}}break;
 case 'focusReset':s.focus=null;break;
 case 'focusFinish':{const f=s.focus;if(f&&['running','paused'].includes(f.status)){const remaining=f.status==='running'?Math.max(0,f.endsAt-now):f.remainingMs;const minutes=Math.floor((f.minutes*60000-remaining)/60000);if(minutes>0)s.sessions.push({id:randomUUID(),taskID:f.taskID,taskTitle:f.title,startedAt:new Date(f.startedAt).toISOString(),minutes});s.focus={...f,status:'finished',remainingMs:0};}break;}
 case 'settings':{s.settings.model=text(p.model,100);if(!s.settings.model)throw new Error('请填写模型名称');for(const k of ['dailyTime','weeklyTime']){if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(p[k]))throw new Error('提醒时间无效');s.settings[k]=p[k];}s.settings.pet=!!p.pet;s.settings.reminders=!!p.reminders;break;}
 default:throw new Error('不支持的操作');
 }return s;
}
function importData(state,data){
 if(!data||typeof data!=='object'||Array.isArray(data))throw new Error('不是有效的团子备份');let found=false;
 if(Array.isArray(data.areas)){if(data.areas.length>100)throw new Error('领域数量超限');for(const a of data.areas){text(a.id,100);text(a.name,100);const i=state.areas.findIndex(x=>x.id===a.id);if(i>=0)state.areas[i]=a;else state.areas.push(a);}}
 if(Array.isArray(data.tasks)){if(data.tasks.length>50000)throw new Error('任务数量超限');for(const raw of data.tasks){text(raw.id,100);const task=validateTask(newTask(raw));const i=state.tasks.findIndex(x=>x.id===task.id);if(i>=0)state.tasks[i]=task;else state.tasks.push(task);}found=true;}
 if(data.currentWeeklyPlan){const p=data.currentWeeklyPlan;state.weeks[weekKey(dayKey(p.weekStart))]={goals:p.goals.map(x=>text(x,500)),notes:text(p.notes||'')};}
 const config=data.configuration;if(config){const sections=[...(config.dailySections||[]),config.sundaySection,config.monthlySection].filter(Boolean);const habits=sections.flatMap(section=>section.items.map(item=>({...item,scope:section.id===config.sundaySection?.id?'sunday':section.id===config.monthlySection?.id?'monthEnd':'everyday'})));if(!habits.length)throw new Error('SOP 模板为空');state.habits=habits;if(Array.isArray(config.timeBlocks))state.blocks=config.timeBlocks;found=true;}
 if(data.schemaVersion===1){for(const k of ['weeks','habits','blocks','completions','reviews','sessions','events'])if(data[k])state[k]=structuredClone(data[k]);found=true;}
 if(data.completionByDay){state.completions={...state.completions,...data.completionByDay};found=true;}
 if(data.reviews&&data.sessions){state.reviews={...state.reviews,...data.reviews};for(const x of data.sessions){if(!state.sessions.some(y=>y.id===x.id))state.sessions.push(x);}found=true;}
 if(!found)throw new Error('未发现任务、SOP 或复盘记录');state.undo=[];return state;
}
module.exports={defaults,active,dayKey,localDay,shiftDay,weekKey,parseCapture,newTask,validateTask,nextDate,habitItems,rangesFree,placeTasks,tickFocus,applyAction,importData};
