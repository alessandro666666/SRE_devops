#!/bin/bash
#write by alessandro jin

# 默认都放到/home/finance/software/路径下
# nginx 1.22.0
#https://nginx.org/download/nginx-1.22.0.tar.gz
# nginx sticky module，可选
#https://bitbucket.org/nginx-goodies/nginx-sticky-module-ng/get/master.tar.gz
# upstream check module，可选
#https://codeload.github.com/yaoweibin/nginx_upstream_check_module/zip/master
#PCRE软件包
#wget https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz
# 以下为lua相关文件
# LuaJIT 2.1（2.0或者2.1都是支持的，官方推荐2.1）
#wget http://luajit.org/download/LuaJIT-2.1.0-beta2.tar.gz
# ngx_devel_kit（NDK）模块
#wget https://github.com/simpl/ngx_devel_kit/archive/v0.3.0.tar.gz --no-check-certificate
# lua nginx module
#wget https://github.com/openresty/lua-nginx-module/archive/v0.10.13.tar.gz --no-check-certificate



# 创建www用户
if ! id -u www &>/dev/null; then
    useradd -r -s /sbin/nologin www
fi

# 安装依赖包
yum install -y gcc gcc-c++ pcre-devel openssl-devel zlib-devel

# 检查文件是否存在
packages=(nginx-1.22.0.tar.gz LuaJIT-2.1.0-beta2.tar.gz nginx_upstream_check_module-master.zip v0.3.0.tar.gz master.tar.gz v0.10.13.tar.gz pcre-8.45.tar.gz)
missing_packages=()
for package in "${packages[@]}"; do
    if [ ! -f "/usr/local/src/$package" ]; then
        missing_packages+=("$package")
    fi
done

# 如果有缺失的包，则输出提示信息
if [ ${#missing_packages[@]} -gt 0 ]; then
    echo "Missing packages:"
    printf '%s\n' "${missing_packages[@]}"
    exit 1
fi

# 解压缩文件
cd /usr/local/src/
for package in "${packages[@]}"; do
    if [[ $package == *.tar.gz ]]; then
        tar -zxvf "$package"
    elif [[ $package == *.zip ]]; then
        unzip "$package"
    fi
done

# 安装 LuaJIT
cd /usr/local/src/LuaJIT-2.1.0-beta2
make PREFIX=/usr/local/luajit
make install PREFIX=/usr/local/luajit
ln -sf luajit-2.1.0-beta2 /usr/local/luajit/bin/luajit

# 修改系统环境变量
echo 'export LUAJIT_LIB=/usr/local/luajit/lib' >> /etc/profile
echo 'export LUAJIT_INC=/usr/local/luajit/include/luajit-2.1' >> /etc/profile
source /etc/profile

# 添加 LuaJIT 库路径到 ld.so.conf
echo '/usr/local/lib' >> /etc/ld.so.conf
echo '/usr/local/luajit/lib' >> /etc/ld.so.conf
ldconfig

# 编译和安装 nginx
cd /usr/local/src/nginx-1.22.0/
./configure --prefix=/usr/local/nginx \
--sbin-path=/usr/local/nginx/sbin/nginx \
--conf-path=/usr/local/nginx/conf/nginx.conf \
--error-log-path=/usr/local/nginx/logs/nginx/error.log \
--http-log-path=/usr/local/nginx/logs/nginx/access.log \
--pid-path=/usr/local/nginx/var/nginx.pid \
--lock-path=/usr/local/nginx/var/nginx.lock \
--http-client-body-temp-path=/usr/local/nginx/nginx_temp/client_body \
--http-proxy-temp-path=/usr/local/nginx/nginx_temp/proxy \
--http-fastcgi-temp-path=/usr/local/nginx/nginx_temp/fastcgi \
--user=www \
--group=www \
--with-cpu-opt=pentium4F \
--with-pcre=/usr/local/src/pcre-8.45 \
--without-select_module \
--without-poll_module \
--with-http_ssl_module \
--with-http_v2_module \
--with-http_realip_module \
--with-http_sub_module \
--with-http_stub_status_module \
--without-http_ssi_module \
--without-http_userid_module \
--with-http_gzip_static_module \
--with-pcre \
--with-stream \
--with-stream_ssl_module \
--without-http_geo_module \
--with-stream_realip_module \
--without-mail_pop3_module \
--without-mail_imap_module \
--without-mail_smtp_module \
--with-http_ssl_module \
--add-module=/usr/local/src/nginx-goodies-nginx-sticky-module-ng-08a395c66e42 \
--add-module=/usr/local/src/nginx_upstream_check_module-master \
--add-module=/usr/local/src/ngx_devel_kit-0.3.0 \
--add-module=/usr/local/src/lua-nginx-module-0.10.13


# 编译 nginx
make
make install

# 创建依赖的temp文件夹
mkdir -pv /usr/local/nginx/nginx_temp/


cat >/usr/lib/systemd/system/nginx.service <<EOF
[Unit]
# 描述服务                                                                                     
Description=nginx - high performance web server  
# 描述服务类别            
After=network.target remote-fs.target nss-lookup.target   
 
# 服务的一些具体运行参数的设置 
[Service]                                                                                 
# 后台运行的形式
Type=forking
# PID文件的路径                                                                         
PIDFile=/usr/local/nginx/var/nginx.pid 
# 启动准备                              
ExecStartPre=/usr/local/nginx/sbin/nginx -t -c /usr/local/nginx/conf/nginx.conf
# 启动命令   
ExecStart=/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf
# 重启命令           
ExecReload=/usr/local/nginx/sbin/nginx -s reload
# 停止命令                                                 
ExecStop=/usr/local/nginx/sbin/nginx -s stop        
# 快速停止                                               
ExecQuit=/usr/local/nginx/sbin/nginx -s quit
# 给服务分配临时空间                         
PrivateTmp=true                                                         
 
# 服务用户的模式 
[Install]
WantedBy=multi-user.target
EOF


systemctl enable nginx
systemctl start nginx
systemctl status nginx
ln -s /usr/local/nginx/sbin/nginx /usr/bin/nginx

#检查nginx是否启动成功
sleep 5  # 等待5秒，确保Logstash有足够的时间启动
if systemctl is-active --quiet nginx; then
    echo "nginx启动成功"
    rm -rf "$0" >> /dev/null  # 如果启动成功则删除脚本本身
else
    echo "nginx启动失败"
fi


