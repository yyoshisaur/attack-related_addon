# attackwithme
/attackを複数のキャラクター同期させるアドオン

(/attackだけでなく、メニューからの攻撃にも対応)

- 使い方

3キャラクター A, B, Cがある場合　(A, B, Cすべてに本アドオンをロードしておく)

Aの戦闘開始に同期してBも戦闘開始する設定(Cは同期させない)

キャラクターAのクライアントで/attackするマスターを設定

        //atkwm master

キャラクターBのクライアントで "同期する" 設定

        //atkwm slave on

キャラクターCのクライアントで "同期しない" 設定

        //atkwm slave off

/attackoff(戦闘解除)も同期する