"""Create fixed symbol-component observations; no runtime or core mutation."""
from pathlib import Path
import argparse,base64,json

HERE=Path(__file__).resolve().parent
def b64(value):
    return base64.b64encode(value.encode('utf-8') if isinstance(value,str) else value).decode('ascii')
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
    if a.output.exists():ap.error('Choose a fresh file; old definitions are preserved')
    pairs=json.loads((HERE.parent/'php-identifiers/comparison-pairs.json').read_text(encoding='utf-8-sig'))
    kinds=['Function','ClassLike','Method','Variable','Property','Parameter','Constant','ClassConstant','Namespace','FunctionImportAlias','ClassImportAlias','ConstantImportAlias']
    rows=[]
    def add(id,kind,left,right,oracle=True,member=False,containers=None):
        row=dict(id=id,kind=kind,left_base64=b64(left),right_base64=b64(right),oracle=oracle,member=member)
        if containers is not None:row.update(left_container_base64=b64(containers[0]),right_container_base64=b64(containers[1]))
        if not oracle:row['contract_equal']=left==right
        rows.append(row)
    for kind in kinds:
        for pair in pairs:add(kind+'-'+pair['id'],kind,pair['left'],pair['right'])
    for id,left,right in [('prefix-ascii','MiXeD\\Value','mixed\\Value'),('leaf-ascii','MiXeD\\Value','mixed\\value'),('prefix-unicode','É\\Value','é\\Value'),('nested-prefix','One\\TwO\\V','one\\two\\V'),('nested-leaf','One\\TwO\\V','one\\two\\v')]:
        add('constant-'+id,'Constant',left,right)
    for kind in ['Function','ClassLike','Method','Variable','Property','Parameter','Constant','ClassConstant','Namespace','FunctionImportAlias','ClassImportAlias','ConstantImportAlias']:
        add(kind+'-raw-80-exact',kind,b'Name\x80',b'Name\x80')
        add(kind+'-raw-ff-distinct',kind,b'Name\xff',b'Name\x80')
    for kind in ['Method','Property','ClassConstant']:
        add(kind+'-container-ascii',kind,'Leaf','Leaf',member=True,containers=('Space\\CaT','space\\cat'))
        add(kind+'-container-leaf-ascii',kind,'Leaf','leaf',member=True,containers=('Space\\CaT','space\\cat'))
        add(kind+'-container-unicode',kind,'Leaf','Leaf',member=True,containers=('É','é'))
    for kind in ['Variable','Constant','ConstantImportAlias']:
        add(kind+'-numeric-symbol',kind,b'8',b'08',oracle=False)
        add(kind+'-embedded-nul',kind,b'A\x00B',b'A\x00B',oracle=False)
    add('function-raw-nul-contract','Function',b'F\x00Z',b'f\x00z',oracle=False)
    rows[-1]['contract_equal']=True
    add('keyword-ascii-contract','Keyword','FUNCTION','function',oracle=False)
    rows[-1]['contract_equal']=True
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'total':len(rows),'oracle':sum(r['oracle'] for r in rows),'contract_only':sum(not r['oracle'] for r in rows)}))
if __name__=='__main__':main()
