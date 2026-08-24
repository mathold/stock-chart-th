/**
 * ตัวรับ log ของเว็บ mathold-stock → เก็บลง Google Sheet
 * =====================================================
 * วางไฟล์นี้ทั้งไฟล์ใน Extensions > Apps Script ของสเปรดชีต แล้ว Deploy เป็น
 * Web app (Execute as: Me / Who has access: Anyone) เอา URL ที่ได้ไปใส่
 * Streamlit Secrets เป็น analytics_url
 *
 * ชีตที่ใช้ (สร้างให้อัตโนมัติ ไม่ต้องทำเอง)
 *   log   — ทุกเหตุการณ์ 1 บรรทัด
 *   สรุป  — ตัวเลขรวม + ตารางรายวัน (กดอัปเดตจากเมนู 📊 สถิติ หรือเปิดชีตใหม่)
 */

// ตั้งรหัสให้ตรงกับ analytics_key ใน Streamlit Secrets — เว้นว่าง = ไม่ตรวจ
var SECRET_KEY = 'เปลี่ยนรหัสนี้ให้ตรงกับใน Secrets';

var LOG_SHEET = 'log';
var SUM_SHEET = 'สรุป';
var HEADERS = ['เวลา (ไทย)', 'วันที่', 'event', 'detail', 'session', 'เวลาที่ชีตรับ'];


/** แอปยิงเข้ามาตรงนี้ */
function doPost(e) {
  try {
    var body = JSON.parse(e.postData.contents);
    if (SECRET_KEY && String(body.key || '') !== SECRET_KEY) {
      return _json({ ok: false, error: 'bad key' });
    }
    var lock = LockService.getScriptLock();
    lock.waitLock(20000);                       // กันสองคนเขียนทับบรรทัดเดียวกัน
    try {
      var sh = _logSheet();
      var t = String(body.time || '');
      sh.appendRow([
        t,
        t.substring(0, 10),                     // วันที่ล้วน ไว้จัดกลุ่มรายวัน
        String(body.event || ''),
        String(body.detail || ''),
        String(body.session || ''),
        new Date()
      ]);
    } finally {
      lock.releaseLock();
    }
    return _json({ ok: true });
  } catch (err) {
    return _json({ ok: false, error: String(err) });
  }
}


/** เปิด URL เดียวกันในเบราว์เซอร์ = ดูตัวเลขสรุปแบบเร็ว ๆ */
function doGet(e) {
  return _json(_stats());
}


/** เมนูในสเปรดชีต */
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('📊 สถิติ')
    .addItem('อัปเดตสรุป', 'refreshSummary')
    .addToUi();
  try { refreshSummary(); } catch (err) {}
}


/** คำนวณตัวเลขสรุปทั้งหมดจากชีต log */
function _stats() {
  var rows = _logSheet().getDataRange().getValues();
  rows.shift();                                  // ตัดหัวตาราง

  var sess = {}, sessMy = {}, byDay = {};
  var opens = 0, presses = 0, entered = 0, locked = 0;

  rows.forEach(function (r) {
    var day = String(r[1] || ''), ev = String(r[2] || '');
    var det = String(r[3] || ''), sid = String(r[4] || '');
    if (!day) return;
    if (!byDay[day]) byDay[day] = { u: {}, press: 0, on: 0 };

    if (sid) { sess[sid] = 1; byDay[day].u[sid] = 1; }

    if (ev === 'open') { opens++; }
    if (ev === 'mysignal') {
      presses++;
      byDay[day].press++;
      if (det === 'on') { entered++; byDay[day].on++; if (sid) sessMy[sid] = 1; }
      if (det === 'locked') { locked++; }
    }
  });

  var days = Object.keys(byDay).sort().reverse();
  return {
    ผู้ใช้ทั้งหมด: Object.keys(sess).length,
    เปิดเว็บรวม: opens,
    กดปุ่ม_MySignal: presses,
    เข้าโหมดสำเร็จ: entered,
    เจอกำแพงรหัส: locked,
    คนที่เคยเข้า_MySignal: Object.keys(sessMy).length,
    รายวัน: days.map(function (d) {
      return [d, Object.keys(byDay[d].u).length, byDay[d].press, byDay[d].on];
    })
  };
}


/** เขียนตัวเลขสรุปลงชีต "สรุป" */
function refreshSummary() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName(SUM_SHEET) || ss.insertSheet(SUM_SHEET);
  sh.clear();

  var s = _stats();
  var head = [
    ['สถิติเว็บ mathold-stock', ''],
    ['อัปเดตล่าสุด', Utilities.formatDate(new Date(), 'Asia/Bangkok', 'd/M/yyyy HH:mm')],
    ['', ''],
    ['ผู้ใช้ทั้งหมด (นับแท็บที่ไม่ซ้ำ)', s['ผู้ใช้ทั้งหมด']],
    ['จำนวนครั้งที่เปิดเว็บ', s['เปิดเว็บรวม']],
    ['', ''],
    ['กดปุ่ม My Signal (ทุกครั้ง)', s['กดปุ่ม_MySignal']],
    ['— เข้าโหมดได้สำเร็จ', s['เข้าโหมดสำเร็จ']],
    ['— กดแล้วเจอกำแพงรหัส', s['เจอกำแพงรหัส']],
    ['คนที่เคยเข้า My Signal ได้ (ไม่ซ้ำ)', s['คนที่เคยเข้า_MySignal']],
    ['', ''],
    ['รายวัน', '']
  ];
  sh.getRange(1, 1, head.length, 2).setValues(head);
  sh.getRange('A1').setFontSize(14).setFontWeight('bold');
  sh.getRange('A12').setFontWeight('bold');

  var cols = [['วันที่', 'คนเข้า (ไม่ซ้ำ)', 'กด My Signal', 'เข้าโหมดสำเร็จ']];
  var table = cols.concat(s['รายวัน']);
  sh.getRange(13, 1, table.length, 4).setValues(table);
  sh.getRange(13, 1, 1, 4).setFontWeight('bold').setBackground('#eeeeee');
  sh.setColumnWidth(1, 230);
  sh.setColumnWidth(2, 130);
  sh.setColumnWidth(3, 130);
  sh.setColumnWidth(4, 130);
}


function _logSheet() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName(LOG_SHEET);
  if (!sh) {
    sh = ss.insertSheet(LOG_SHEET);
    sh.appendRow(HEADERS);
    sh.getRange(1, 1, 1, HEADERS.length).setFontWeight('bold');
    sh.setFrozenRows(1);
  }
  return sh;
}


function _json(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
