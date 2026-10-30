import Foundation

// make_appicon_layers.swift - exports the Bough icon as SEPARATE vector layers
// (same coordinates as Scripts/make_appicon.swift) for Icon Composer:
//
//   background.svg       opaque full-bleed warm-paper gradient
//   foreground.svg       branch + leaves + commit nodes (leaves at 90% alpha
//                        for glass depth; crisp edges, no feathering)
//   foreground-mono.svg  single-color alpha-only variant for monochrome/tint
//
// Usage: xcrun swift Scripts/make_appicon_layers.swift
// Then in Icon Composer: File > New > drag each SVG onto its layer slot.

let layerDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("build/icon-layers")
try FileManager.default.createDirectory(at: layerDir, withIntermediateDirectories: true)

// Same geometry as make_appicon.swift (1024 design space, y-down).
let branchPath = "M 205 875 C 330 700, 555 430, 690 185"
let forkPath = "M 470 585 C 650 505, 765 410, 870 330"
// Leaves in local coords, placed via transform (angle in degrees).
let leaf1 = "translate(360,725) rotate(-120.32)"
let leaf2 = "translate(690,430) rotate(-85.94)"
let leafShape = "M 0 0 Q 87.5 -50, 175 0 Q 87.5 50, 0 0 Z"

func svgDocument(content: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
    \(content)
    </svg>
    """
}

let background = """
    <defs>
      <linearGradient id="paper" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#F8F2E7"/>
        <stop offset="1" stop-color="#E7DDC4"/>
      </linearGradient>
    </defs>
    <rect width="1024" height="1024" fill="url(#paper)"/>
    """

let foreground = """
    <g stroke-linecap="round" stroke-linejoin="round" fill="none">
      <path d="\(branchPath)" stroke="#3E5C50" stroke-width="92"/>
      <path d="\(forkPath)" stroke="#3E5C50" stroke-width="66"/>
    </g>
    <path d="\(leafShape)" fill="#6B9080" fill-opacity="0.9" transform="\(leaf1)"/>
    <path d="\(leafShape)" fill="#6B9080" fill-opacity="0.9" transform="\(leaf2)"/>
    <circle cx="690" cy="185" r="62" fill="#D98E4A"/>
    <circle cx="870" cy="330" r="48" fill="#6B9080"/>
    """

// Monochrome variant: alpha-only shapes, single luminance (spec: tint layers
// use the alpha channel; leave detail to Icon Composer's specular pass).
let foregroundMono = """
    <g stroke="#000000" stroke-linecap="round" stroke-linejoin="round" fill="none">
      <path d="\(branchPath)" stroke-width="92"/>
      <path d="\(forkPath)" stroke-width="66"/>
    </g>
    <path d="\(leafShape)" fill="#000000" transform="\(leaf1)"/>
    <path d="\(leafShape)" fill="#000000" transform="\(leaf2)"/>
    <circle cx="690" cy="185" r="62" fill="#000000"/>
    <circle cx="870" cy="330" r="48" fill="#000000"/>
    """

try svgDocument(content: background).write(to: layerDir.appendingPathComponent("background.svg"),
                                           atomically: true, encoding: .utf8)
try svgDocument(content: foreground).write(to: layerDir.appendingPathComponent("foreground.svg"),
                                           atomically: true, encoding: .utf8)
try svgDocument(content: foregroundMono).write(to: layerDir.appendingPathComponent("foreground-mono.svg"),
                                               atomically: true, encoding: .utf8)
print("layers written to build/icon-layers/ (background, foreground, foreground-mono)")
