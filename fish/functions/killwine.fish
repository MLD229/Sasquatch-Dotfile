function killwine
    wineserver -k
    sleep 2
    pkill -9 -f 'PlariumPlay|wine|winedevice.exe|services.exe|plugplay.exe|svchost.exe|explorer.exe|rpcss.exe'
end
