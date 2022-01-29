const vk = @import("vulkan");


pub const BaseDispatch = vk.BaseWrapper(&.{
    .createInstance,
});

pub const InstanceDispatch = vk.InstanceWrapper(&.{
    .destroyInstance,
    .createDebugUtilsMessengerEXT,
    .destroyDebugUtilsMessengerEXT,
    .createDevice,
    .destroySurfaceKHR,
    .enumeratePhysicalDevices,
    .getPhysicalDeviceProperties,
    .getPhysicalDeviceMemoryProperties,
    .getPhysicalDeviceFeatures,
    .enumerateDeviceExtensionProperties,
    .getPhysicalDeviceSurfaceFormatsKHR,
    .getPhysicalDeviceSurfacePresentModesKHR,
    .getPhysicalDeviceSurfaceCapabilitiesKHR,
    .getPhysicalDeviceQueueFamilyProperties,
    .getPhysicalDeviceSurfaceSupportKHR,
    .getDeviceProcAddr,
});

pub const DeviceDispatch = vk.DeviceWrapper(&.{
    .destroyDevice,
    .getDeviceQueue,
    .createSemaphore,
    .createFence,
    .createImageView,
    .destroyImageView,
    .destroySemaphore,
    .destroyFence,
    .getSwapchainImagesKHR,
    .createSwapchainKHR,
    .destroySwapchainKHR,
    .acquireNextImageKHR,
    .deviceWaitIdle,
    .waitForFences,
    .resetFences,
    .queueSubmit,
    .queuePresentKHR,
    .createCommandPool,
    .destroyCommandPool,
    .allocateCommandBuffers,
    .freeCommandBuffers,
    .queueWaitIdle,
    .createShaderModule,
    .destroyShaderModule,
    .createPipelineLayout,
    .destroyPipelineLayout,
    .createRenderPass,
    .destroyRenderPass,
    .createGraphicsPipelines,
    .destroyPipeline,
    .createFramebuffer,
    .destroyFramebuffer,
    .beginCommandBuffer,
    .endCommandBuffer,
    .allocateMemory,
    .freeMemory,
    .createBuffer,
    .destroyBuffer,
    .getBufferMemoryRequirements,
    .mapMemory,
    .unmapMemory,
    .bindBufferMemory,
    .cmdBeginRenderPass,
    .cmdEndRenderPass,
    .cmdBindPipeline,
    .cmdDraw,
    .cmdSetViewport,
    .cmdSetScissor,
    .cmdBindVertexBuffers,
    .cmdCopyBuffer,
});