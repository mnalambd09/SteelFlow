import {create} from 'zustand';
import {createClient} from '@supabase/supabase-js';
import {products as sampleProducts,type Product} from './data';

const url=import.meta.env.VITE_SUPABASE_URL as string|undefined;
const key=import.meta.env.VITE_SUPABASE_ANON_KEY as string|undefined;
export const supabase=url&&key?createClient(url,key):null;
export async function fetchCatalog():Promise<Product[]>{
 if(!supabase)return sampleProducts;
 const {data,error}=await supabase.from('products').select('id,name,sku,description,material,price,unit,category:categories(name),brand:brands(name),product_specifications(name,value),inventory(quantity),product_images(storage_path,alt_text,is_primary)').eq('status','active').order('name');
 if(error)throw error;
 if(!data?.length)return sampleProducts;
 return data.map((row:any)=>{const specs=Object.fromEntries((row.product_specifications||[]).map((s:any)=>[s.name,s.value]));const imageRow=(row.product_images||[]).find((i:any)=>i.is_primary)||(row.product_images||[])[0];const image=imageRow?supabase!.storage.from('product-media').getPublicUrl(imageRow.storage_path).data.publicUrl:sampleProducts.find(p=>p.id===row.id)?.image||'';return {id:row.id,name:row.name,sku:row.sku,description:row.description,material:row.material||'',price:Number(row.price),unit:row.unit,category:row.category?.name||'Industrial Supplies',brand:row.brand?.name||'SteelFlow',stock:row.inventory?.quantity||0,image,specs} as Product});
}
type CartLine={product:Product;quantity:number};
type Store={cart:CartLine[];wishlist:string[];compare:string[];viewed:string[];add:(p:Product,n?:number)=>void;qty:(id:string,n:number)=>void;remove:(id:string)=>void;toggleWish:(id:string)=>void;toggleCompare:(id:string)=>void;view:(id:string)=>void;clear:()=>void};
const persist=(s:Partial<Store>)=>localStorage.setItem('steelflow-state',JSON.stringify({...JSON.parse(localStorage.getItem('steelflow-state')||'{}'),...s}));
const initial=()=>{try{return JSON.parse(localStorage.getItem('steelflow-state')||'{}')}catch{return {}}};
export const useStore=create<Store>((set)=>({cart:initial().cart||[],wishlist:initial().wishlist||[],compare:initial().compare||[],viewed:initial().viewed||[],
 add:(p,n=1)=>set(s=>{const cart=s.cart.some(x=>x.product.id===p.id)?s.cart.map(x=>x.product.id===p.id?{...x,quantity:x.quantity+n}:x):[...s.cart,{product:p,quantity:n}];persist({cart});return {cart}}),
 qty:(id,n)=>set(s=>{const cart=s.cart.map(x=>x.product.id===id?{...x,quantity:Math.max(1,n)}:x);persist({cart});return {cart}}),
 remove:(id)=>set(s=>{const cart=s.cart.filter(x=>x.product.id!==id);persist({cart});return {cart}}),
 toggleWish:(id)=>set(s=>{const wishlist=s.wishlist.includes(id)?s.wishlist.filter(x=>x!==id):[...s.wishlist,id];persist({wishlist});return {wishlist}}),
 toggleCompare:(id)=>set(s=>{const compare=s.compare.includes(id)?s.compare.filter(x=>x!==id):s.compare.length<4?[...s.compare,id]:s.compare;persist({compare});return {compare}}),
 view:(id)=>set(s=>{const viewed=[id,...s.viewed.filter(x=>x!==id)].slice(0,6);persist({viewed});return {viewed}}),
 clear:()=>set(()=>{persist({cart:[]});return {cart:[]}})}));
export const money=(n:number)=>new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(n);
export async function submitRequest(table:'rfqs'|'orders',payload:Record<string,unknown>){
 if(!supabase)throw new Error('Supabase is not configured. Connect a project using steel-flow/.env before submitting requests.');
 const {data:{user}}=await supabase.auth.getUser();
 if(!user)throw new Error('Sign in to your SteelFlow account before submitting.');
 if(table==='orders'){
  const {data,error}=await supabase.functions.invoke('create-order',{body:payload});
  if(error)throw new Error(error.message);
  if(data?.error)throw new Error(data.error);
  return {id:data.order_id as string};
 }
 const files=(payload._files as File[]|undefined)||[];const items=(payload.items as Array<{product_id?:string;quantity:number;size?:string;grade?:string}>|undefined)||[];delete payload._files;delete payload.items;
 const {data,error}=await supabase.from(table).insert({...payload,user_id:user.id,status:'Submitted'}).select('id').single();
 if(error)throw new Error(error.message);
 if(items.length){const {error:itemError}=await supabase.from('rfq_items').insert(items.map(item=>({rfq_id:data.id,product_id:item.product_id,quantity:item.quantity,size:item.size,grade:item.grade})));if(itemError)throw new Error(`RFQ ${data.id} was created, but line items could not be saved: ${itemError.message}`)}
 for(const file of files){
  const path=`${user.id}/${data.id}/${crypto.randomUUID()}-${file.name.replace(/[^\w.-]/g,'_')}`;
  const {error:uploadError}=await supabase.storage.from('rfq-files').upload(path,file,{upsert:false});
  if(uploadError)throw new Error(`RFQ ${data.id} was created, but ${file.name} could not be uploaded: ${uploadError.message}`);
  const {error:rowError}=await supabase.from('rfq_files').insert({rfq_id:data.id,storage_path:path,file_name:file.name,mime_type:file.type,size_bytes:file.size});
  if(rowError)throw new Error(`RFQ ${data.id} was created, but its file record could not be saved: ${rowError.message}`);
 }
 return data;
}
