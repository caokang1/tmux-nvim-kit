# 用法: python3 build_index.py <ttyd原始index.html> <字体目录> <输出index.html>
import base64, io, sys
from fontTools.ttLib import TTFont

src, fontdir, out = sys.argv[1:4]
FAMILY = "JetBrainsMono NFM"

def woff2_b64(path):
    f = TTFont(path)
    f.flavor = "woff2"
    buf = io.BytesIO()
    f.save(buf)
    return base64.b64encode(buf.getvalue()).decode()

faces = []
# 只嵌入常规和粗体，斜体由浏览器合成，页面体积减半
for name, weight, style in [("Regular", 400, "normal"), ("Bold", 700, "normal")]:
    data = woff2_b64(f"{fontdir}/JetBrainsMonoNerdFontMono-{name}.ttf")
    faces.append(f'@font-face{{font-family:"{FAMILY}";src:url(data:font/woff2;base64,{data}) format("woff2");'
                 f'font-weight:{weight};font-style:{style};font-display:block}}')

html = open(src, encoding="utf-8").read()
tag = '<script type="text/javascript">'
assert html.count(tag) == 1
# 先等字体加载完再运行 ttyd 的脚本，否则 xterm.js 会按后备字体测量字符宽度，图标错位
html = html.replace(tag, '<script type="text/x-deferred" id="ttyd-main">')
loader = ('<script>Promise.all(["400","700"].map(function(w){return document.fonts.load(w+\' 15px "' + FAMILY + '"\')}))'
          '.catch(function(){}).then(function(){var s=document.createElement("script");'
          's.text=document.getElementById("ttyd-main").text;document.body.appendChild(s)})</script>')
# ttyd 不支持 OSC 52（程序通过终端写剪贴板），tmux / Neovim 里复制的内容到不了浏览器。
# 这里补上：收到 OSC 52 就写入本机剪贴板。内网 http 地址不是"安全上下文"，
# navigator.clipboard 不可用，退回到 execCommand("copy")（按键触发后短时间内允许）。
osc52 = r"""<script>(function(){
function fallback(t){var a=document.createElement("textarea");a.value=t;a.style.position="fixed";a.style.opacity="0";
document.body.appendChild(a);a.select();try{document.execCommand("copy")}catch(e){}document.body.removeChild(a);
if(window.term)window.term.focus()}
function copy(t){if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(t).catch(function(){fallback(t)})}else{fallback(t)}
toast()}
function toast(){var d=document.createElement("div");d.textContent="已复制";
d.style.cssText="position:fixed;top:12px;right:16px;z-index:99;padding:4px 10px;border-radius:4px;background:#2B2D30;color:#BCBEC4;font:13px sans-serif;border:1px solid #393B40";
document.body.appendChild(d);setTimeout(function(){d.remove()},800)}
function decode(b){var s=atob(b),u=new Uint8Array(s.length);for(var i=0;i<s.length;i++)u[i]=s.charCodeAt(i);return new TextDecoder().decode(u)}
var timer=setInterval(function(){var t=window.term;if(!t||!t.parser)return;clearInterval(timer);
t.parser.registerOscHandler(52,function(data){var i=data.indexOf(";");var b=i>=0?data.slice(i+1):data;
if(b&&b!=="?"){try{copy(decode(b))}catch(e){}}return true})},200);
})()</script>"""
# 终端里 Ctrl+Shift+字母 和 Ctrl+字母 发出的是同一个按键，Neovim 分不出来（IDEA 的 Ctrl+Shift+F 等就没法用）。
# 这里改为发送扩展按键编码 ESC [ <小写字母编码> ; 6 u（6 = Ctrl+Shift），tmux 开了 extended-keys 会原样转给 Neovim。
# Ctrl+Shift+V / C 留给浏览器粘贴 / 复制；Ctrl+Shift+N / T / W 浏览器不让网页拦截，按了也到不了这里。
ctrl_shift = r"""<script>(function(){
var keep={V:1,C:1};
var timer=setInterval(function(){var t=window.term;if(!t||!t.attachCustomKeyEventHandler)return;clearInterval(timer);
t.attachCustomKeyEventHandler(function(e){
if(e.type!=="keydown"||!e.ctrlKey||!e.shiftKey||e.altKey||e.metaKey)return true;
var m=/^Key([A-Z])$/.exec(e.code);if(!m||keep[m[1]])return true;
e.preventDefault();t.input("\x1b["+(m[1].charCodeAt(0)+32)+";6u",true);return false})},200);
})()</script>"""
# xterm.js 会丢弃 Shift+滚轮 和触控板左右滑动（只认上下滚动），Neovim 收不到横向滚动。
# 这里在程序开启了鼠标模式时，把它们转成 Shift+滚轮 的鼠标事件（SGR 编码，按钮 68 = 向左、69 = 向右）发给 tmux。
hscroll = r"""<script>(function(){
var acc=0;
var timer=setInterval(function(){var t=window.term;if(!t||!t.attachCustomWheelEventHandler||!t.element)return;clearInterval(timer);
t.attachCustomWheelEventHandler(function(e){
var dx=e.shiftKey?(e.deltaX||e.deltaY):(Math.abs(e.deltaX)>Math.abs(e.deltaY)?e.deltaX:0);
if(!dx)return true;
if(!t.modes||t.modes.mouseTrackingMode==="none")return true;
try{
var r=t.element.querySelector(".xterm-screen").getBoundingClientRect();
var cw=r.width/t.cols,ch=r.height/t.rows;
var col=Math.max(1,Math.min(t.cols,Math.floor((e.clientX-r.left)/cw)+1)),row=Math.max(1,Math.min(t.rows,Math.floor((e.clientY-r.top)/ch)+1));
}catch(err){return true}
e.preventDefault();
acc+=e.deltaMode===1?dx*40:dx;
if(Math.abs(acc)<40)return false;
var b=acc>0?69:68,n=Math.min(5,Math.floor(Math.abs(acc)/40));acc=0;
for(var i=0;i<n;i++)t.input("\x1b[<"+b+";"+col+";"+row+"M",true);
return false})},200);
})()</script>"""
html = html.replace("</body>", loader + osc52 + ctrl_shift + hscroll + "</body>")
# 页面底色与编辑器背景一致，避免终端外露出白边
page_css = "html,body{background:#1E1F22;margin:0}"
html = html.replace("<head>", "<head><style>" + page_css + "".join(faces) + "</style>", 1)
open(out, "w", encoding="utf-8").write(html)
print("written", out, len(html) // 1024, "KB")
