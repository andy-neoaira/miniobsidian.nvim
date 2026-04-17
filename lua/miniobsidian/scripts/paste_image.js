/**
 * paste_image.js — macOS JXA (JavaScript for Automation) script
 *
 * 职责：从 macOS 剪贴板读取图片，根据来源自动判断处理方式：
 *       1. 若剪贴板含文件路径（Finder 复制文件）→ 直接复制文件，保留原格式
 *       2. 否则（截图 / 浏览器复制图片）→ 通过 NSImage 流水线转换并保存
 *       保存完成后将实际使用的扩展名输出到 stdout。
 *
 * 调用方式：
 *   osascript -l JavaScript paste_image.js <base_path>
 *   base_path 不含扩展名，脚本自动追加正确后缀。
 *
 * 退出码：
 *   0  成功，stdout 输出扩展名（"png" / "jpg" / "gif" 等）
 *   1  失败，stderr 输出包含以下关键字之一：
 *      NO_IMAGE       — 剪贴板中没有图片或图片文件
 *      NOT_IMAGE_FILE — 剪贴板中是文件但不是图片格式
 *      TIFF_FAILED    — 无法获取图片 TIFF 表示
 *      BITMAP_FAILED  — 无法创建位图表示
 *      CONVERT_FAILED — 格式转换失败
 *      WRITE_FAILED   — 文件写入失败
 *      MISSING_PATH   — 未提供目标路径参数
 */

/* global $, ObjC */
ObjC.import("AppKit");
ObjC.import("Foundation");

/** 从路径字符串中提取扩展名（小写，不含点）*/
function getExt(filePath) {
  const parts = filePath.split(".");
  return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : "";
}

function run(argv) {
  if (!argv || argv.length < 1) {
    throw new Error("MISSING_PATH");
  }

  const pb = $.NSPasteboard.generalPasteboard;
  const basePath = argv[0];

  // ── 路径 1：Finder 复制的文件（NSFilenamesPboardType）──────────────
  // 当用户在 Finder 中 Cmd+C 一个图片文件时，剪贴板包含文件路径列表，
  // 此时直接复制文件以保留原始格式（HEIC / WEBP / GIF 等均完整保留）。
  const SUPPORTED_IMAGE_EXTS = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp", "svg"];

  const fileList = pb.propertyListForType($("NSFilenamesPboardType"));
  if (!fileList.isNil() && fileList.count > 0) {
    const srcPath = fileList.objectAtIndex(0).js;
    const srcExt = getExt(srcPath);

    if (!SUPPORTED_IMAGE_EXTS.includes(srcExt)) {
      throw new Error("NOT_IMAGE_FILE");
    }

    // jpeg → jpg 规范化，其余保留原始扩展名
    const normalExt = srcExt === "jpeg" ? "jpg" : srcExt;
    const outputPath = basePath + "." + normalExt;

    // 用 NSData 逐字节复制，避免格式损失，也无需 NSError Ref 参数
    const srcURL = $.NSURL.fileURLWithPath($(srcPath));
    const data = $.NSData.dataWithContentsOfURL(srcURL);
    if (data.isNil()) {
      throw new Error("WRITE_FAILED");
    }

    const dstURL = $.NSURL.fileURLWithPath($(outputPath));
    if (!data.writeToURLAtomically(dstURL, true)) {
      throw new Error("WRITE_FAILED");
    }

    return normalExt;
  }

  // ── 路径 2：截图 / 浏览器复制图片（NSImage 流水线）───────────────
  const image = $.NSImage.alloc.initWithPasteboard(pb);
  if (image.isNil()) {
    throw new Error("NO_IMAGE");
  }

  // 遍历 NSArray 逐项转换（比 .js 属性更安全，可过滤 null 条目）
  const nsTypes = pb.types;
  const typeCount = nsTypes.isNil() ? 0 : nsTypes.count;
  const types = [];
  for (let i = 0; i < typeCount; i++) {
    const t = nsTypes.objectAtIndex(i).js;
    if (t) types.push(t);
  }

  // UTI 优先级：JPEG > GIF > PNG（PNG 为兜底，覆盖 TIFF/截图等所有其他情形）
  let ext, fileType;
  if (types.includes("public.jpeg")) {
    ext = "jpg";
    fileType = $.NSBitmapImageFileTypeJPEG;
  } else if (types.includes("com.compuserve.gif")) {
    ext = "gif";
    fileType = $.NSBitmapImageFileTypeGIF;
  } else {
    ext = "png";
    fileType = $.NSBitmapImageFileTypePNG;
  }

  const tiff = image.TIFFRepresentation;
  if (tiff.isNil()) {
    throw new Error("TIFF_FAILED");
  }

  const bitmap = $.NSBitmapImageRep.imageRepWithData(tiff);
  if (bitmap.isNil()) {
    throw new Error("BITMAP_FAILED");
  }

  const data = bitmap.representationUsingTypeProperties(fileType, $());
  if (data.isNil()) {
    throw new Error("CONVERT_FAILED");
  }

  const outputPath = basePath + "." + ext;
  const url = $.NSURL.fileURLWithPath($(outputPath));
  if (!data.writeToURLAtomically(url, true)) {
    throw new Error("WRITE_FAILED");
  }

  return ext;
}
