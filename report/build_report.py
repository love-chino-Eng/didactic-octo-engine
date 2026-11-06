# -*- coding: utf-8 -*-
"""按模板生成实验报告 docx（保留模板封面与标题样式，正文由 markdown 内容填充）。"""
import re, sys
from docx import Document
from docx.shared import Pt, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

TPL = r"C:/Users/Administrator.DESKTOP-V49HBOA/Downloads/实验报告模板（信号采集与分析系统）.docx"
OUT = r"D:/vivado/reaction_test/report/实验报告_反应力测试仪.docx"
MD = r"D:/vivado/reaction_test/report/md/"

BODY_FONT_CN, BODY_FONT_EN, BODY_SIZE = "宋体", "Times New Roman", 12
CODE_FONT, CODE_SIZE = "Consolas", 9


def style_run(run, cn=BODY_FONT_CN, en=BODY_FONT_EN, size=BODY_SIZE, bold=False):
    run.font.name = en
    run.font.size = Pt(size)
    run.bold = bold
    rPr = run._element.get_or_add_rPr()
    rFonts = rPr.find(qn("w:rFonts"))
    if rFonts is None:
        rFonts = OxmlElement("w:rFonts")
        rPr.append(rFonts)
    rFonts.set(qn("w:eastAsia"), cn)
    rFonts.set(qn("w:ascii"), en)
    rFonts.set(qn("w:hAnsi"), en)


def add_body(cursor, text, indent=True, size=BODY_SIZE, bold=False):
    p = cursor.insert_paragraph_before()
    p.style = "Normal"
    pf = p.paragraph_format
    pf.first_line_indent = Pt(size * 2) if indent else Pt(0)
    pf.line_spacing = 1.5
    pf.space_before = Pt(0)
    pf.space_after = Pt(0)
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    r = p.add_run(text)
    style_run(r, size=size, bold=bold)
    return p


def add_h2(cursor, text):
    p = cursor.insert_paragraph_before()
    p.style = "Normal"
    pf = p.paragraph_format
    pf.first_line_indent = Pt(0)
    pf.space_before = Pt(9)
    pf.space_after = Pt(3)
    pf.line_spacing = 1.5
    r = p.add_run(text)
    style_run(r, cn="黑体", en="Times New Roman", size=12, bold=True)
    return p


def add_code(cursor, text):
    p = cursor.insert_paragraph_before()
    p.style = "Normal"
    pf = p.paragraph_format
    pf.first_line_indent = Pt(0)
    pf.left_indent = Pt(6)
    pf.space_before = Pt(3)
    pf.space_after = Pt(3)
    pf.line_spacing = 1.0
    lines = text.split("\n")
    for i, ln in enumerate(lines):
        r = p.add_run(ln)
        style_run(r, cn="宋体", en=CODE_FONT, size=CODE_SIZE)
        if i != len(lines) - 1:
            r.add_break()
    return p


def set_cell(cell, text, bold=False, size=10.5):
    cell.text = ""
    p = cell.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    pf = p.paragraph_format
    pf.first_line_indent = Pt(0)
    pf.line_spacing = 1.0
    pf.space_before = Pt(0)
    pf.space_after = Pt(0)
    r = p.add_run(text)
    style_run(r, size=size, bold=bold)


def add_table(doc, cursor, rows):
    header, body = rows[0], rows[1:]
    ncol = len(header)
    t = doc.add_table(rows=0, cols=ncol)
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    hr = t.add_row()
    for i, h in enumerate(header):
        set_cell(hr.cells[i], h, bold=True)
    for row in body:
        tr = t.add_row()
        for i in range(ncol):
            set_cell(tr.cells[i], row[i] if i < len(row) else "")
    cursor._p.addprevious(t._tbl)
    # 表格后补一个极小空段，避免与下文粘连
    gap = cursor.insert_paragraph_before()
    gap.paragraph_format.space_before = Pt(0)
    gap.paragraph_format.space_after = Pt(0)
    gap.paragraph_format.line_spacing = 1.0
    return t


def parse_md(path):
    blocks, buf = [], []
    in_code, code_buf = False, []
    table_buf = []

    def flush_par():
        nonlocal buf
        if buf:
            blocks.append(("p", "".join(buf).strip()))
            buf = []

    def flush_table():
        nonlocal table_buf
        if table_buf:
            rows = []
            for i, line in enumerate(table_buf):
                if i == 1 and re.match(r"^\|[\s\-:|]+\|$", line.strip()):
                    continue
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                rows.append(cells)
            blocks.append(("table", rows))
            table_buf = []

    for raw in open(path, encoding="utf-8").read().split("\n"):
        line = raw.rstrip()
        if line.startswith("```"):
            if in_code:
                blocks.append(("code", "\n".join(code_buf)))
                code_buf, in_code = [], False
            else:
                flush_par(); flush_table()
                in_code = True
            continue
        if in_code:
            code_buf.append(line)
            continue
        if line.startswith("!["):
            flush_par(); flush_table()
            inner=line.strip()[3:-2].strip("[]")
            blocks.append(("img", inner))
            continue
        if line.startswith("|"):
            flush_par()
            table_buf.append(line)
            continue
        flush_table()
        if line.startswith("## "):
            flush_par()
            blocks.append(("h2", line[3:].strip()))
        elif line.startswith("# "):
            flush_par()
            blocks.append(("h1", line[2:].strip()))
        elif not line.strip():
            flush_par()
        elif re.match(r"^(\d+\.\s|-\s)", line):
            flush_par()
            buf.append(line)
        else:
            buf.append(line)
    flush_par(); flush_table()
    if in_code and code_buf:
        blocks.append(("code", "\n".join(code_buf)))
    return blocks


def emit(doc, cursor, blocks, h1_size=14):
    for kind, val in blocks:
        if kind == "h1":
            p = cursor.insert_paragraph_before()
            p.style = "Heading 1"
            r = p.add_run(val)
            style_run(r, cn="黑体", en="Times New Roman", size=h1_size, bold=True)
        elif kind == "h2":
            add_h2(cursor, val)
        elif kind == "code":
            add_code(cursor, val)
        elif kind == "img":
            pic = cursor.insert_paragraph_before()
            pic.style = "Normal"
            pic.alignment = WD_ALIGN_PARAGRAPH.CENTER
            pic.paragraph_format.first_line_indent = Pt(0)
            pic.paragraph_format.space_before = Pt(6)
            run = pic.add_run()
            run.add_picture(MD + val, width=Cm(15.5))
        elif kind == "table":
            # 表题（紧邻上一段时已在 md 中给出），直接建表
            add_table(doc, cursor, val)
        else:
            txt = val.replace("**", "").replace("`", "")
            if re.match(r"^[图表]\s?\d", txt) and len(txt) < 60:
                p = cursor.insert_paragraph_before()
                p.style = "Normal"
                pf = p.paragraph_format
                pf.first_line_indent = Pt(0)
                pf.space_before = Pt(6)
                pf.space_after = Pt(3)
                pf.line_spacing = 1.0
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                r = p.add_run(txt)
                style_run(r, size=10.5, bold=True)
            else:
                is_item = bool(re.match(r"^(\d+\.|-\s)", txt))
                add_body(cursor, txt, indent=not is_item)


def clean_inline(s):
    return s.replace("**", "").replace("`", "")


def find_para(doc, text):
    for p in doc.paragraphs:
        if p.text.strip() == text:
            return p
    return None


def main():
    doc = Document(TPL)

    # 1) 封面
    for p in doc.paragraphs[:20]:
        for r in p.runs:
            if "信号采集与分析系统" in r.text:
                r.text = r.text.replace("信号采集与分析系统", "基于 Zynq 的反应力测试仪（数字打地鼠）")
        if p.text.strip().replace("：", "").strip() in ("实验日期", "实验日期:"):
            for r in p.runs[1:]:
                r.text = ""
            if p.runs:
                p.runs[0].text = "实验日期：\t\t2026 年 11 月 6 日"

    # 2) 删除“实现方案及关键模块设计”之后、模板中多余的空 Heading 1 段
    paras = doc.paragraphs
    for i, p in enumerate(paras):
        if p.style.name == "Heading 1" and not p.text.strip():
            p._p.getparent().remove(p._p)

    # 3) 定位各节锚点（下一节标题），内容插在其前
    order = ["实验目的", "实验原理", "实验器材", "实现方案及关键模块设计",
             "实验结果与分析", "实验总结"]
    anchors = {}
    for name in order:
        anchors[name] = find_para(doc, name)
    note = None
    for p in doc.paragraphs:
        if p.text.strip().startswith("注：报告中的图表"):
            note = p
    files = ["s1.md", "s2.md", "s3.md", "s4.md", "s5.md", "s6.md"]

    heads = [find_para(doc, n) for n in order]
    for idx, hp in enumerate(heads):
        if hp is not None and hp.runs:
            first = hp.runs[0]
            if not re.match(r"^\d", first.text):
                first.text = "%d  %s" % (idx + 1, first.text)
    for idx, name in enumerate(order):
        cursor = heads[idx + 1] if idx + 1 < len(heads) else note
        blocks = parse_md(MD + files[idx])
        emit(doc, cursor, blocks)

    # 4) 附录：放在文末（删掉模板的“注”说明段）
    if note is not None:
        cursor = note
        brk = cursor.insert_paragraph_before()
        brk.paragraph_format.space_before = Pt(0)
        brk.paragraph_format.space_after = Pt(0)
        brk.add_run().add_break(WD_BREAK.PAGE)
        blocks = parse_md(MD + "app.md")
        emit(doc, cursor, blocks)
        # 附录插完后删除“注”段
        note._p.getparent().remove(note._p)

    doc.save(OUT)
    print("saved", OUT)


if __name__ == "__main__":
    main()
