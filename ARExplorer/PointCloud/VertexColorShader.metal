//
//  VertexColorShader.metal
//  ARExplorer
//
//  Surface shader that reads vertex colors for point cloud rendering.
//

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>

using namespace metal;

[[visible]]
void vertexColorSurface(realitykit::surface_parameters params)
{
    // Read vertex color from the color attribute (float4 rgba)
    float4 vertexColorRGBA = params.geometry().color();
    half3 vertexColor = half3(vertexColorRGBA.rgb);
    
    // Set as emissive so it's unlit and shows true color
    params.surface().set_emissive_color(vertexColor);
    
    // Set base color to black (emissive provides all color)
    params.surface().set_base_color(half3(0.0));
    
    // No roughness/metallic needed for point cloud
    params.surface().set_roughness(1.0);
    params.surface().set_metallic(0.0);
}
