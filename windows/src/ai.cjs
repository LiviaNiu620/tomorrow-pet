'use strict';
const {randomUUID}=require('node:crypto');
const {active,dayKey,weekKey,habitItems}=require('./core.cjs');
const taskSchema={type:'object',properties:{task_id:{type:['string','null']},input_item_id:{type:['string','null']},title:{type:'string'},area:{type:'string'},reason:{type:'string'},estimated_minutes:{type:'integer',minimum:5,maximum:480},priority:{type:'string',enum:['high','medium','low','none']},source:{type:'string',enum:['existing_task','calendar_preparation','user_input']}},required:['task_id','input_item_id','title','area','reason','estimated_minutes','priority','source'],additionalProperties:false};
const schema={type:'object',properties:{summary:{type:'string'},top_three:{type:'array',items:taskSchema,maxItems:3},additional_tasks:{type:'array',items:taskSchema,maxItems:25},workload_assessment:{type:'string'},notes:{type:'string'}},required:['summary','top_three','additional_tasks','workload_assessment','notes'],additionalProperties:false};
function payload(state,date,input){
 const lines=String(input||'').split(/\r?\n/).map(x=>x.trim()).filter(Boolean);if(lines.length>20)throw new Error('补充事项最多 20 条');if(lines.some(x=>x.length>1000))throw new Error('补充事项过长');
 return {tomorrow:date,active_tasks:state.tasks.filter(active).map(t=>({task_id:t.id,title:t.title,area:state.areas.find(a=>a.id===t.areaID)?.name||'未分类',priority:t.priority,status:t.status,estimated_minutes:t.estimatedMinutes,planned_date:t.plannedDate,due_date:t.dueDate})),calendar_events:state.events.filter(e=>dayKey(e.startDate)<=date&&dayKey(e.endDate)>=date).map(e=>({title:e.title,start:e.startDate,end:e.endDate,all_day:e.isAllDay})),weekly_plan:state.weeks[weekKey(date)]||null,daily_sop:habitItems(state,date).filter(h=>h.isPlanningContext).map(h=>({time:h.time,title:h.title,section:h.sectionTitle})),user_input_items:lines.map(text=>({input_item_id:randomUUID(),text}))};
}
function validatePlan(plan,context){
 if(!plan||!Array.isArray(plan.top_three)||!Array.isArray(plan.additional_tasks)||plan.top_three.length>3||plan.additional_tasks.length>25)throw new Error('AI 计划格式无效');
 for(const key of ['summary','workload_assessment','notes'])if(typeof plan[key]!=='string')throw new Error('AI 计划格式无效');
 const ids=new Set(context.active_tasks.map(t=>t.task_id));const expected=new Set(context.user_input_items.map(x=>x.input_item_id)),received=new Set(),seen=new Set();
 for(const t of [...plan.top_three,...plan.additional_tasks]){
 if(typeof t.title!=='string'||!t.title.trim()||t.title.length>1000||typeof t.reason!=='string'||typeof t.area!=='string'||!Number.isInteger(t.estimated_minutes)||t.estimated_minutes<5||t.estimated_minutes>480||!['high','medium','low','none'].includes(t.priority))throw new Error('AI 任务字段无效');
 if(t.source==='existing_task'){if(!ids.has(t.task_id)||seen.has(t.task_id)||t.input_item_id)throw new Error('AI 返回了无效或重复的任务');seen.add(t.task_id);}
 else if(t.source==='user_input'){if(t.task_id||!expected.has(t.input_item_id)||received.has(t.input_item_id))throw new Error('AI 补充事项映射无效');received.add(t.input_item_id);}
 else if(t.source!=='calendar_preparation'||t.task_id||t.input_item_id)throw new Error('AI 来源无效');
 t.id=randomUUID();
 }
 if(received.size!==expected.size)throw new Error('AI 遗漏了补充事项，请重试');return plan;
}
async function generate(state,date,input,key,fetcher=fetch){
 if(!key)throw new Error('请先在设置中保存 OpenAI API Key');const context=payload(state,date,input);
 const response=await fetcher('https://api.openai.com/v1/responses',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},signal:AbortSignal.timeout(90000),body:JSON.stringify({model:state.settings.model,input:[{role:'system',content:'你是温和、务实的中文规划助手。输出简体中文。挑选最多三个重点，保留至少30%弹性，避开日历和SOP。已有任务原样返回task_id，不重复；每条user_input_items必须恰好保留一次，source为user_input，input_item_id原样返回。不要虚构日程或创建重复习惯。仅日历确实需要准备时可以提出calendar_preparation新任务。'},{role:'user',content:JSON.stringify(context)}],text:{format:{type:'json_schema',name:'tomorrow_plan',strict:true,schema}}})});
 if(!response.ok)throw new Error(`AI 请求失败（HTTP ${response.status}），请检查密钥、模型和额度`);
 const data=await response.json();if(data.status&&data.status!=='completed')throw new Error('AI 回复未完成，请重试');const output=(data.output||[]).flatMap(o=>o.content||[]).find(x=>x.type==='output_text')?.text;if(!output)throw new Error('AI 未返回计划');return validatePlan(JSON.parse(output),context);
}
module.exports={schema,payload,validatePlan,generate};
