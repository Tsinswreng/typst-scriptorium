#import "_.typ": *
#show: _Show

#H[部署][
	先clone
	```sh
	git clone https://github.com/Tsinswreng/typst-scriptorium tsinswreng-scriptorium
	```
	
	#H[本地相對路徑引用][
		````typst
		#import "tsinswreng-scriptorium/_.typ": *
		#show: _Show
		````
	]
	
	#H[註冊成 本地包][
		註冊成 本地包 之後,
		則可不用相對路徑引用,
		保持寫法一致。
		
		以Windows爲例:
````powershell
$Repo = "tsinswreng-scriptorium" # 替換成你clone的scriptorium的絕對路徑
New-Item -ItemType Directory -Force "$env:APPDATA\typst\packages\local\tsinswreng-scriptorium" | Out-Null
New-Item -ItemType Junction -Path "$env:APPDATA\typst\packages\local\tsinswreng-scriptorium\0.1.0" -Target $Repo
````

引用本地包
````typst
#import "@local/tsinswreng-scriptorium:0.1.0": *
#show: _Show
````

	]
]






