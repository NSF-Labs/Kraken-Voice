#include <jni.h>
#include <dlfcn.h>
#include <vulkan/vulkan.h>
#include <string>
#include <vector>
#include <sstream>
#include <cstdint>

namespace {
std::string quote(const std::string &s) {
  std::ostringstream out; out << '"';
  for (unsigned char c : s) {
    if (c == '"' || c == '\\') out << '\\' << c;
    else if (c < 32 || c >= 127) { const char *h="0123456789abcdef"; out << "\\u00" << h[c>>4] << h[c&15]; }
    else out << c;
  }
  return out.str() + '"';
}
struct Library {
  void *handle;
  explicit Library(const char *name): handle(dlopen(name, RTLD_NOW | RTLD_LOCAL)) {}
  ~Library() { if (handle) dlclose(handle); }
  template<class T> T symbol(const char *name) { return reinterpret_cast<T>(dlsym(handle, name)); }
};
std::string loader(const char *name) {
  Library lib(name);
  if (lib.handle) return "{\"loadable\":true,\"executionVerified\":false}";
  const char *error=dlerror();
  return "{\"loadable\":false,\"error\":" + quote(error ? error : "unknown") + "}";
}
// Only enumerate devices. No OpenCL context, queue, program or kernel is created.
std::string opencl() {
  Library lib("libOpenCL.so");
  if (!lib.handle) { const char *e=dlerror(); return "{\"loadable\":false,\"error\":"+quote(e?e:"unknown")+"}"; }
  using Id=void*; using UInt=uint32_t; using Int=int32_t;
  auto platforms=lib.symbol<Int(*)(UInt,Id*,UInt*)>("clGetPlatformIDs");
  auto devices=lib.symbol<Int(*)(Id,uint64_t,UInt,Id*,UInt*)>("clGetDeviceIDs");
  auto info=lib.symbol<Int(*)(Id,UInt,size_t,void*,size_t*)>("clGetDeviceInfo");
  if (!platforms || !devices || !info) return "{\"loadable\":true,\"error\":\"enumeration symbols missing\"}";
  UInt n=0; Int status=platforms(0,nullptr,&n);
  std::string out="{\"loadable\":true,\"platformStatus\":"+std::to_string(status)+",\"devices\":[";
  bool first=true;
  if (status==0 && n>0 && n<=64) {
    std::vector<Id> ps(n);
    if (platforms(n,ps.data(),nullptr)==0) for (auto p:ps) {
      UInt count=0; Int ds=devices(p,0xFFFFFFFFULL,0,nullptr,&count);
      if (!first) out+=","; first=false;
      out+="{\"enumerationStatus\":"+std::to_string(ds)+",\"items\":[";
      if (ds==0 && count>0 && count<=64) {
        std::vector<Id> ids(count);
        if (devices(p,0xFFFFFFFFULL,count,ids.data(),nullptr)==0) for (UInt i=0;i<count;i++) {
          if(i) out+=",";
          auto field=[&](UInt key) { char value[4096]={}; Int r=info(ids[i],key,sizeof(value)-1,value,nullptr); return r==0?quote(value):"null"; };
          out+="{\"name\":"+field(0x102B)+",\"vendor\":"+field(0x102C)+",\"driver\":"+field(0x102D)+",\"version\":"+field(0x102F)+"}";
        }
      }
      out+="]}";
    }
  }
  return out+"],\"inferenceVerified\":false}";
}
std::string vulkan() {
  Library lib("libvulkan.so");
  if (!lib.handle) return "{\"loadable\":false}";
  auto create=lib.symbol<PFN_vkCreateInstance>("vkCreateInstance");
  auto destroy=lib.symbol<PFN_vkDestroyInstance>("vkDestroyInstance");
  auto enumerate=lib.symbol<PFN_vkEnumeratePhysicalDevices>("vkEnumeratePhysicalDevices");
  auto props=lib.symbol<PFN_vkGetPhysicalDeviceProperties>("vkGetPhysicalDeviceProperties");
  if (!create || !destroy || !enumerate || !props) return "{\"error\":\"symbols missing\"}";
  VkInstanceCreateInfo ci{}; ci.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  VkInstance instance{}; VkResult status=create(&ci,nullptr,&instance);
  std::string out="{\"instanceStatus\":"+std::to_string(status)+",\"devices\":[";
  if (status==VK_SUCCESS) {
    uint32_t count=0; VkResult result=enumerate(instance,&count,nullptr);
    if (result==VK_SUCCESS && count>0 && count<=64) {
      std::vector<VkPhysicalDevice> ids(count);
      result=enumerate(instance,&count,ids.data());
      if (result==VK_SUCCESS) for(uint32_t i=0;i<count;i++) {
        VkPhysicalDeviceProperties p{}; props(ids[i],&p);
        if(i) out+=",";
        out+="{\"name\":"+quote(p.deviceName)+",\"vendorId\":"+std::to_string(p.vendorID)+",\"deviceId\":"+std::to_string(p.deviceID)+",\"apiVersion\":"+std::to_string(p.apiVersion)+",\"driverVersion\":"+std::to_string(p.driverVersion)+"}";
      }
    }
    destroy(instance,nullptr);
    out+="],\"enumerationStatus\":"+std::to_string(result);
  } else out+="]";
  return out+"}";
}
}
extern "C" JNIEXPORT jstring JNICALL
Java_org_krak_1en_voice_HardwareProbeTest_nativeDiscovery(JNIEnv *env,jobject) {
  std::string json="{\"opencl\":"+opencl()+",\"vulkan\":"+vulkan()+",\"qualcommLibraries\":{\"libcdsprpc.so\":"+loader("libcdsprpc.so")+",\"libQnnHtp.so\":"+loader("libQnnHtp.so")+"}}";
  return env->NewStringUTF(json.c_str());
}
