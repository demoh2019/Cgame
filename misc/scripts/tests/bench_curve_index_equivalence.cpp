#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <random>
#include <vector>

static int legacy_index(const std::vector<float> &points, float x, uint64_t *reads = nullptr) {
    int imin=0, imax=(int)points.size()-1;
    while (imax-imin>1) {
        int m=(imin+imax)/2;
        float a=points[m];
        float b=points[m+1];
        if(reads) *reads += 2;
        if(a<x && b<x) imin=m;
        else if(a>x) imax=m;
        else return m;
    }
    if(reads) ++*reads;
    if(x>points[imax]) return imax;
    return imin;
}
static int optimized_index(const std::vector<float> &points,float x,uint64_t *reads = nullptr) {
    int imin=0,imax=(int)points.size()-1;
    while(imax-imin>1) {
        int m=(imin+imax)/2;
        float a=points[m];
        if(reads) ++*reads;
        if(a<x) {
            float b=points[m+1];
            if(reads) ++*reads;
            if(b<x) imin=m;
            else return m;
        } else if(a>x) imax=m;
        else return m;
    }
    if(reads) ++*reads;
    if(x>points[imax]) return imax;
    return imin;
}
int main(){
    std::mt19937 rng(1234567);
    uint64_t ncases=0;
    for(int n=2;n<=160;n++) {
        std::vector<float> p(n);
        float v=0;
        for(float &k:p){v+=float(rng()%8);k=v;}
        for(int x=-4;x<=int(v)+4;x++) {
            float offset=x*0.5f;
            if(legacy_index(p,offset)!=optimized_index(p,offset)){std::cerr<<"Mismatch n="<<n<<" x="<<offset<<"\n";return 1;}
            ++ncases;
        }
        for(float k:p) {if(legacy_index(p,k)!=optimized_index(p,k)){std::cerr<<"Exact mismatch\n";return 2;}++ncases;}
        const float nan=std::numeric_limits<float>::quiet_NaN();
        if(legacy_index(p,nan)!=optimized_index(p,nan)){std::cerr<<"NaN mismatch\n";return 3;}++ncases;
    }
    std::cout<<"PASS equivalence "<<ncases<<" cases\n";
    const int num_points=64;
    std::vector<float> p(num_points); for(int i=0;i<num_points;i++)p[i]=i*1.f;
    std::vector<float> queries(1000000);
    std::uniform_real_distribution<float> dist(-5.f,69.f);
    for(auto &q:queries)q=dist(rng);
    uint64_t oldreads=0,newreads=0,oldsum=0,newsum=0;
    auto tick=std::chrono::steady_clock::now();
    for(int repeat=0; repeat<5;repeat++)for(float q:queries)oldsum+=legacy_index(p,q,&oldreads);
    auto old_us=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-tick).count();
    tick=std::chrono::steady_clock::now();
    for(int repeat=0; repeat<5;repeat++)for(float q:queries)newsum+=optimized_index(p,q,&newreads);
    auto new_us=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-tick).count();
    std::cout<<"legacy: "<<old_us<<"us reads="<<oldreads<<" result="<<oldsum<<"\n";
    std::cout<<"optimized: "<<new_us<<"us reads="<<newreads<<" result="<<newsum<<"\n";
    return oldsum==newsum&&newreads<=oldreads?0:4;
}
