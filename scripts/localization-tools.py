"""Swift string scanning for offline localization coverage validation."""
# A small Swift string lexer: include nested interpolation strings, skip comments.
def strings(s):
 out=[]
 def read_string(i):
  start=i; i+=1; parts=[]; expressions=[]; plain=[]
  while i<len(s):
   if s[i]=='"':
    parts.append(''.join(plain));return i+1,parts,expressions
   if s[i]=='\\' and i+1<len(s):
    if s[i+1]=='(':
     parts.append(''.join(plain));plain=[];a=i+2;i=a;depth=1
     while i<len(s) and depth:
      if s[i]=='"':
       end,_,_=read_string(i);i=end;continue
      if s[i]=='(':depth+=1
      if s[i]==')':depth-=1
      i+=1
     expressions.append(s[a:i-1]);continue
    plain.append(s[i:i+2]);i+=2;continue
   plain.append(s[i]);i+=1
  raise ValueError('Unclosed string')
 i=0
 while i<len(s):
  if s.startswith('//',i):
   pos=s.find('\n',i);i=len(s) if pos<0 else pos+1;continue
  if s.startswith('/*',i):
   depth=1;i+=2
   while depth:
    if s.startswith('/*',i):depth+=1;i+=2
    elif s.startswith('*/',i):depth-=1;i+=2
    else:i+=1
   continue
  if s[i]=='"':
   end,parts,expr=read_string(i);out.append((i,end,parts,expr));i=end
  else:i+=1
 return out
