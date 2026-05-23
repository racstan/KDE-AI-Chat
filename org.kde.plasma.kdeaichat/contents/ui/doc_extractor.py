#!/usr/bin/env python3
import sys
import os
import json
import base64
import subprocess
import mimetypes
import zipfile
import xml.etree.ElementTree as ET
import urllib.parse

def extract_docx_text(path):
    # Try pandoc first
    try:
        result = subprocess.run(['pandoc', '-f', 'docx', '-t', 'markdown', path], capture_output=True, text=True, check=True)
        return result.stdout
    except Exception:
        pass
    
    # Fallback to direct XML parsing
    try:
        with zipfile.ZipFile(path) as docx:
            xml_content = docx.read('word/document.xml')
            root = ET.fromstring(xml_content)
            paragraphs = []
            namespace = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
            for p in root.iter(namespace + 'p'):
                p_text = []
                for t in p.iter(namespace + 't'):
                    if t.text:
                        p_text.append(t.text)
                paragraphs.append("".join(p_text))
            return "\n".join(paragraphs)
    except Exception as e:
        return f"Error extracting DOCX text: {str(e)}"

def extract_pdf_text(path):
    try:
        result = subprocess.run(['pdftotext', path, '-'], capture_output=True, text=True, check=True)
        return result.stdout
    except Exception as e:
        return f"Error extracting PDF text (is pdftotext installed?): {str(e)}"

def extract_single_file(file_path):
    if not os.path.exists(file_path):
        return {
            "status": "error",
            "message": f"File not found: {file_path}"
        }

    filename = os.path.basename(file_path)
    file_size = os.path.getsize(file_path)
    
    # Guess mime type
    mime_type, _ = mimetypes.guess_type(file_path)
    ext = os.path.splitext(filename)[1].lower()

    if not mime_type:
        if ext == '.docx':
            mime_type = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        elif ext == '.csv':
            mime_type = 'text/csv'
        elif ext == '.pdf':
            mime_type = 'application/pdf'
        else:
            mime_type = 'application/octet-stream'

    try:
        # Check if it's an image
        if mime_type.startswith('image/') or ext in ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp']:
            with open(file_path, 'rb') as f:
                img_data = f.read()
                base64_data = base64.b64encode(img_data).decode('utf-8')
            
            actual_mime = mime_type if mime_type.startswith('image/') else 'image/jpeg'
            return {
                "status": "success",
                "type": "image",
                "filename": filename,
                "path": file_path,
                "size": file_size,
                "mimeType": actual_mime,
                "content": base64_data
            }
        elif ext == '.pdf':
            text = extract_pdf_text(file_path)
            return {
                "status": "success",
                "type": "text",
                "filename": filename,
                "path": file_path,
                "size": file_size,
                "mimeType": "application/pdf",
                "content": text
            }
        elif ext == '.docx':
            text = extract_docx_text(file_path)
            return {
                "status": "success",
                "type": "text",
                "filename": filename,
                "path": file_path,
                "size": file_size,
                "mimeType": mime_type,
                "content": text
            }
        elif mime_type.startswith('text/') or ext in ['.csv', '.txt', '.md', '.json', '.xml', '.yaml', '.yml', '.js', '.ts', '.py', '.sh', '.html', '.css']:
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    text = f.read()
            except UnicodeDecodeError:
                with open(file_path, 'r', encoding='latin-1') as f:
                    text = f.read()
            
            return {
                "status": "success",
                "type": "text",
                "filename": filename,
                "path": file_path,
                "size": file_size,
                "mimeType": mime_type or 'text/plain',
                "content": text
            }
        else:
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    text = f.read()
                return {
                    "status": "success",
                    "type": "text",
                    "filename": filename,
                    "path": file_path,
                    "size": file_size,
                    "mimeType": 'text/plain',
                    "content": text
                }
            except Exception:
                return {
                    "status": "error",
                    "message": f"Unsupported file type: {mime_type}"
                }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

def get_clipboard_targets():
    # Try wl-paste first (Wayland)
    try:
        res = subprocess.run(['wl-paste', '-l'], capture_output=True, text=True, check=True)
        return res.stdout.splitlines()
    except Exception:
        pass
    
    # Try xclip (X11)
    try:
        res = subprocess.run(['xclip', '-selection', 'clipboard', '-t', 'TARGETS', '-o'], capture_output=True, text=True, check=True)
        return res.stdout.splitlines()
    except Exception:
        pass
    
    return []

def get_clipboard_data(mime_type):
    # Try wl-paste first (Wayland)
    try:
        res = subprocess.run(['wl-paste', '-t', mime_type], capture_output=True, check=True)
        return res.stdout
    except Exception:
        pass
    
    # Try xclip (X11)
    try:
        res = subprocess.run(['xclip', '-selection', 'clipboard', '-t', mime_type, '-o'], capture_output=True, check=True)
        return res.stdout
    except Exception:
        pass
    
    return None

def handle_clipboard():
    targets = get_clipboard_targets()
    
    # 1. Check for text/uri-list (files copied in file manager)
    has_uri_list = False
    for t in targets:
        if 'uri-list' in t:
            has_uri_list = True
            break
            
    if has_uri_list:
        data = get_clipboard_data('text/uri-list')
        if data:
            try:
                uri_str = data.decode('utf-8')
            except Exception:
                uri_str = data.decode('latin-1')
            
            lines = [line.strip() for line in uri_str.splitlines() if line.strip()]
            files_extracted = []
            
            for line in lines:
                if line.startswith('file://'):
                    path = urllib.parse.unquote(line[7:])
                    file_info = extract_single_file(path)
                    if file_info and file_info.get("status") == "success":
                        files_extracted.append(file_info)
            
            if files_extracted:
                print(json.dumps({
                    "status": "success",
                    "mode": "files",
                    "files": files_extracted
                }))
                return
                
    # 2. Check for image targets
    has_image = False
    img_mime = 'image/png'
    for t in targets:
        if t.startswith('image/'):
            has_image = True
            img_mime = t
            break
            
    if has_image:
        img_bytes = get_clipboard_data(img_mime)
        if img_bytes:
            import tempfile
            suffix = mimetypes.guess_extension(img_mime) or '.png'
            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp_file:
                tmp_file.write(img_bytes)
                temp_path = tmp_file.name
            
            base64_data = base64.b64encode(img_bytes).decode('utf-8')
            filename = os.path.basename(temp_path)
            
            print(json.dumps({
                "status": "success",
                "mode": "image",
                "file": {
                    "type": "image",
                    "name": filename,
                    "path": temp_path,
                    "size": len(img_bytes),
                    "mimeType": img_mime,
                    "content": base64_data
                }
            }))
            return

    print(json.dumps({
        "status": "empty",
        "message": "Clipboard does not contain files or images"
    }))

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"status": "error", "message": "No file path provided"}))
        return

    arg = sys.argv[1]
    if arg == '--clipboard':
        handle_clipboard()
    else:
        result = extract_single_file(arg)
        print(json.dumps(result))

if __name__ == '__main__':
    main()
