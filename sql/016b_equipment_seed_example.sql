-- =====================================================
-- 016b — Equipment Seed (ملف اختياري — لا يُشغَّل تلقائيًا)
-- ⚠️ لا تشغّل هذا الملف إلا بعد اعتماد المعدات الفعلية من المالك.
--    الأسماء أدناه قوالب عامة — عدّلها لتطابق inventory مأوى الحقيقي.
-- التشغيل: Supabase → SQL Editor → عدّل الصفوف → Run (تكراره آمن عبر الاسم)
-- =====================================================

INSERT INTO equipment (name, type) VALUES
    ('Body — Full-frame', 'camera'),
    ('Lens 16-35mm f/2.8', 'lens'),
    ('Lens 24-70mm f/2.8', 'lens'),
    ('Drone 4K', 'drone'),
    ('Gimbal', 'gimbal'),
    ('360 Camera', 'vr360')
ON CONFLICT DO NOTHING;

-- التحقق:
-- SELECT id, name, type, active FROM equipment ORDER BY type, name;
