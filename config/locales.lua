-----------------------------------------------------------------------
-- LOCALES — Translations for MathStoreDemon-v3
-- Change Config.Locale in config.lua to use a different language.
--
-- NEW LANGUAGES CAN BE REQUESTED!
-- Contact math0001 on Discord to request a new language.
-- Novos idiomas podem ser solicitados! Contate math0001 no Discord.
-----------------------------------------------------------------------

Locales = {}

-- ==================== PORTUGUES (BRASIL) ====================
Locales['pt-BR'] = {
    -- Wings
    ['wings_equipped']     = 'Asas equipadas! (cor %s)',
    ['wings_removed']      = 'Asas removidas',
    ['wings_failed']       = 'Falha ao criar asas',
    ['no_permission']      = 'Sem permissao',
    ['invalid_color']      = 'Cor invalida (1-%s)',
    ['flight_equip_first'] = 'Equipe as asas primeiro! (/%s)',
    ['massive_cleanup']    = 'Removidas %s asas',
    ['color_changed']      = 'Cor das asas alterada para %s',
    ['loading']            = 'Carregando...',
    ['keybind_toggle']     = 'Abrir/Fechar Asas',
    ['keybind_fly']        = 'Ativar/Desativar Voo',
    ['keybind_hud']        = 'Abrir/Fechar HUD Demon',
    -- Tail
    ['tail_equipped']      = 'Cauda equipada! (cor %s)',
    ['tail_removed']       = 'Cauda removida',
    ['tail_failed']        = 'Falha ao criar cauda',
    ['tail_invalid_color'] = 'Cor de cauda invalida (1-%s)',
    ['tail_color_changed'] = 'Cor da cauda alterada para %s',
    ['tail_locked']        = 'Voce nao pode equipar a cauda no momento',
    -- Permissions / Cooldowns
    ['wings_locked']       = 'Voce nao pode equipar asas no momento',
    ['cooldown_wait']      = 'Aguarde %s segundos para usar novamente',
    -- Auth
    ['auth_no_key']        = 'ERRO: Nenhuma key configurada no server.cfg!',
    ['auth_add_line']      = 'Adicione a seguinte linha no seu server.cfg:',
    ['auth_replace']       = 'Substitua AP-XXXX-XXXX-XXXX pela key recebida na compra.',
    ['auth_contact']       = 'Contato: math0001 no Discord para suporte.',
    ['auth_not_found']     = 'A KEY informada NAO EXISTE no sistema.',
    ['auth_check_cfg']     = 'Verifique se digitou corretamente no server.cfg.',
    ['auth_format']        = 'Formato: set %s "AP-XXXX-XXXX-XXXX"',
    ['auth_disabled']      = 'A SUA KEY FOI BLOQUEADA e voce perdeu o acesso ao produto.',
    ['auth_disabled_reason'] = 'Isso pode ter ocorrido por violacao de termos ou pedido de reembolso.',
    ['auth_disabled_contact'] = 'Entre em contato com math0001 no Discord para mais informacoes.',
    ['auth_wrong_product'] = 'Essa KEY pertence a OUTRO PRODUTO, nao ao Demon V3.',
    ['auth_wrong_product2'] = 'Cada produto tem sua propria key. Verifique no painel.',
    ['auth_connection']    = 'ERRO DE CONEXAO com o painel: HTTP %s',
    ['auth_connection2']   = 'Verifique sua internet e tente novamente.',
    ['auth_connection3']   = 'Se o problema persistir, contate math0001 no Discord.',
    ['auth_shutdown']      = 'Resource desativado por falha de autenticacao.',
}

-- ==================== ENGLISH (US) ====================
Locales['en-US'] = {
    -- Wings
    ['wings_equipped']     = 'Wings equipped! (color %s)',
    ['wings_removed']      = 'Wings removed',
    ['wings_failed']       = 'Failed to create wings',
    ['no_permission']      = 'No permission',
    ['invalid_color']      = 'Invalid color (1-%s)',
    ['flight_equip_first'] = 'Equip wings first! (/%s)',
    ['massive_cleanup']    = 'Removed %s wings',
    ['color_changed']      = 'Wing color changed to %s',
    ['loading']            = 'Loading...',
    ['keybind_toggle']     = 'Open/Close Wings',
    ['keybind_fly']        = 'Toggle Wing Flight',
    ['keybind_hud']        = 'Open/Close Demon HUD',
    -- Tail
    ['tail_equipped']      = 'Tail equipped! (color %s)',
    ['tail_removed']       = 'Tail removed',
    ['tail_failed']        = 'Failed to create tail',
    ['tail_invalid_color'] = 'Invalid tail color (1-%s)',
    ['tail_color_changed'] = 'Tail color changed to %s',
    ['tail_locked']        = 'You cannot equip the tail right now',
    -- Permissions / Cooldowns
    ['wings_locked']       = 'You cannot equip wings right now',
    ['cooldown_wait']      = 'Wait %s seconds before using again',
    -- Auth
    ['auth_no_key']        = 'ERROR: No key configured in server.cfg!',
    ['auth_add_line']      = 'Add the following line to your server.cfg:',
    ['auth_replace']       = 'Replace AP-XXXX-XXXX-XXXX with the key received on purchase.',
    ['auth_contact']       = 'Contact: math0001 on Discord for support.',
    ['auth_not_found']     = 'The KEY entered DOES NOT EXIST in the system.',
    ['auth_check_cfg']     = 'Check that you typed it correctly in server.cfg.',
    ['auth_format']        = 'Format: set %s "AP-XXXX-XXXX-XXXX"',
    ['auth_disabled']      = 'YOUR KEY HAS BEEN BLOCKED and you lost access to the product.',
    ['auth_disabled_reason'] = 'This may have occurred due to terms violation or refund request.',
    ['auth_disabled_contact'] = 'Contact math0001 on Discord for more information.',
    ['auth_wrong_product'] = 'This KEY belongs to ANOTHER PRODUCT, not Demon V3.',
    ['auth_wrong_product2'] = 'Each product has its own key. Check your panel.',
    ['auth_connection']    = 'CONNECTION ERROR with the panel: HTTP %s',
    ['auth_connection2']   = 'Check your internet and try again.',
    ['auth_connection3']   = 'If the problem persists, contact math0001 on Discord.',
    ['auth_shutdown']      = 'Resource disabled due to authentication failure.',
}

-- ==================== ESPANOL ====================
Locales['es'] = {
    -- Wings
    ['wings_equipped']     = 'Alas equipadas! (color %s)',
    ['wings_removed']      = 'Alas removidas',
    ['wings_failed']       = 'Error al crear alas',
    ['no_permission']      = 'Sin permiso',
    ['invalid_color']      = 'Color invalido (1-%s)',
    ['flight_equip_first'] = 'Equipa las alas primero! (/%s)',
    ['massive_cleanup']    = 'Removidas %s alas',
    ['color_changed']      = 'Color de alas cambiado a %s',
    ['loading']            = 'Cargando...',
    ['keybind_toggle']     = 'Abrir/Cerrar Alas',
    ['keybind_fly']        = 'Activar/Desactivar Vuelo',
    ['keybind_hud']        = 'Abrir/Cerrar HUD Demon',
    -- Tail
    ['tail_equipped']      = 'Cola equipada! (color %s)',
    ['tail_removed']       = 'Cola removida',
    ['tail_failed']        = 'Error al crear la cola',
    ['tail_invalid_color'] = 'Color de cola invalido (1-%s)',
    ['tail_color_changed'] = 'Color de la cola cambiado a %s',
    ['tail_locked']        = 'No puedes equipar la cola en este momento',
    -- Permissions / Cooldowns
    ['wings_locked']       = 'No puedes equipar alas en este momento',
    ['cooldown_wait']      = 'Espera %s segundos para usar de nuevo',
    -- Auth
    ['auth_no_key']        = 'ERROR: Ninguna key configurada en server.cfg!',
    ['auth_add_line']      = 'Agrega la siguiente linea en tu server.cfg:',
    ['auth_replace']       = 'Reemplaza AP-XXXX-XXXX-XXXX por la key recibida en la compra.',
    ['auth_contact']       = 'Contacto: math0001 en Discord para soporte.',
    ['auth_not_found']     = 'La KEY ingresada NO EXISTE en el sistema.',
    ['auth_check_cfg']     = 'Verifica que la escribiste correctamente en server.cfg.',
    ['auth_format']        = 'Formato: set %s "AP-XXXX-XXXX-XXXX"',
    ['auth_disabled']      = 'TU KEY FUE BLOQUEADA y perdiste el acceso al producto.',
    ['auth_disabled_reason'] = 'Esto pudo haber ocurrido por violacion de terminos o solicitud de reembolso.',
    ['auth_disabled_contact'] = 'Contacta a math0001 en Discord para mas informacion.',
    ['auth_wrong_product'] = 'Esta KEY pertenece a OTRO PRODUCTO, no a Demon V3.',
    ['auth_wrong_product2'] = 'Cada producto tiene su propia key. Verifica en el panel.',
    ['auth_connection']    = 'ERROR DE CONEXION con el panel: HTTP %s',
    ['auth_connection2']   = 'Verifica tu internet e intenta de nuevo.',
    ['auth_connection3']   = 'Si el problema persiste, contacta a math0001 en Discord.',
    ['auth_shutdown']      = 'Resource desactivado por falla de autenticacion.',
}

-- ==================== FRANCAIS ====================
Locales['fr'] = {
    -- Wings
    ['wings_equipped']     = 'Ailes equipees ! (couleur %s)',
    ['wings_removed']      = 'Ailes retirees',
    ['wings_failed']       = 'Echec de la creation des ailes',
    ['no_permission']      = 'Pas de permission',
    ['invalid_color']      = 'Couleur invalide (1-%s)',
    ['flight_equip_first'] = 'Equipez les ailes d\'abord ! (/%s)',
    ['massive_cleanup']    = '%s ailes supprimees',
    ['color_changed']      = 'Couleur des ailes changee en %s',
    ['loading']            = 'Chargement...',
    ['keybind_toggle']     = 'Ouvrir/Fermer Ailes',
    ['keybind_fly']        = 'Activer/Desactiver Vol',
    ['keybind_hud']        = 'Ouvrir/Fermer HUD Demon',
    -- Tail
    ['tail_equipped']      = 'Queue equipee ! (couleur %s)',
    ['tail_removed']       = 'Queue retiree',
    ['tail_failed']        = 'Echec de la creation de la queue',
    ['tail_invalid_color'] = 'Couleur de queue invalide (1-%s)',
    ['tail_color_changed'] = 'Couleur de la queue changee en %s',
    ['tail_locked']        = 'Vous ne pouvez pas equiper la queue pour le moment',
    -- Permissions / Cooldowns
    ['wings_locked']       = 'Vous ne pouvez pas equiper d\'ailes pour le moment',
    ['cooldown_wait']      = 'Attendez %s secondes avant de reutiliser',
    -- Auth
    ['auth_no_key']        = 'ERREUR : Aucune key configuree dans server.cfg !',
    ['auth_add_line']      = 'Ajoutez la ligne suivante dans votre server.cfg :',
    ['auth_replace']       = 'Remplacez AP-XXXX-XXXX-XXXX par la key recue a l\'achat.',
    ['auth_contact']       = 'Contact : math0001 sur Discord pour le support.',
    ['auth_not_found']     = 'La KEY saisie N\'EXISTE PAS dans le systeme.',
    ['auth_check_cfg']     = 'Verifiez que vous l\'avez correctement saisie dans server.cfg.',
    ['auth_format']        = 'Format : set %s "AP-XXXX-XXXX-XXXX"',
    ['auth_disabled']      = 'VOTRE KEY A ETE BLOQUEE et vous avez perdu l\'acces au produit.',
    ['auth_disabled_reason'] = 'Cela peut etre du a une violation des conditions ou une demande de remboursement.',
    ['auth_disabled_contact'] = 'Contactez math0001 sur Discord pour plus d\'informations.',
    ['auth_wrong_product'] = 'Cette KEY appartient a un AUTRE PRODUIT, pas a Demon V3.',
    ['auth_wrong_product2'] = 'Chaque produit a sa propre key. Verifiez dans le panneau.',
    ['auth_connection']    = 'ERREUR DE CONNEXION avec le panneau : HTTP %s',
    ['auth_connection2']   = 'Verifiez votre internet et reessayez.',
    ['auth_connection3']   = 'Si le probleme persiste, contactez math0001 sur Discord.',
    ['auth_shutdown']      = 'Resource desactive suite a un echec d\'authentification.',
}

-- ==================== PORTUGUES (PORTUGAL) ====================
Locales['pt-PT'] = {
    -- Wings
    ['wings_equipped']     = 'Asas equipadas! (cor %s)',
    ['wings_removed']      = 'Asas removidas',
    ['wings_failed']       = 'Falha ao criar asas',
    ['no_permission']      = 'Sem permissao',
    ['invalid_color']      = 'Cor invalida (1-%s)',
    ['flight_equip_first'] = 'Equipe as asas primeiro! (/%s)',
    ['massive_cleanup']    = 'Removidas %s asas',
    ['color_changed']      = 'Cor das asas alterada para %s',
    ['loading']            = 'A carregar...',
    ['keybind_toggle']     = 'Abrir/Fechar Asas',
    ['keybind_fly']        = 'Ativar/Desativar Voo',
    ['keybind_hud']        = 'Abrir/Fechar HUD Demon',
    -- Tail
    ['tail_equipped']      = 'Cauda equipada! (cor %s)',
    ['tail_removed']       = 'Cauda removida',
    ['tail_failed']        = 'Falha ao criar cauda',
    ['tail_invalid_color'] = 'Cor de cauda invalida (1-%s)',
    ['tail_color_changed'] = 'Cor da cauda alterada para %s',
    ['tail_locked']        = 'Nao pode equipar a cauda neste momento',
    -- Permissions / Cooldowns
    ['wings_locked']       = 'Nao pode equipar asas neste momento',
    ['cooldown_wait']      = 'Aguarde %s segundos para usar novamente',
    -- Auth
    ['auth_no_key']        = 'ERRO: Nenhuma key configurada no server.cfg!',
    ['auth_add_line']      = 'Adicione a seguinte linha no seu server.cfg:',
    ['auth_replace']       = 'Substitua AP-XXXX-XXXX-XXXX pela key recebida na compra.',
    ['auth_contact']       = 'Contacto: math0001 no Discord para suporte.',
    ['auth_not_found']     = 'A KEY inserida NAO EXISTE no sistema.',
    ['auth_check_cfg']     = 'Verifique se escreveu corretamente no server.cfg.',
    ['auth_format']        = 'Formato: set %s "AP-XXXX-XXXX-XXXX"',
    ['auth_disabled']      = 'A SUA KEY FOI BLOQUEADA e perdeu o acesso ao produto.',
    ['auth_disabled_reason'] = 'Isto pode ter ocorrido por violacao de termos ou pedido de reembolso.',
    ['auth_disabled_contact'] = 'Entre em contacto com math0001 no Discord para mais informacoes.',
    ['auth_wrong_product'] = 'Esta KEY pertence a OUTRO PRODUTO, nao ao Demon V3.',
    ['auth_wrong_product2'] = 'Cada produto tem a sua propria key. Verifique no painel.',
    ['auth_connection']    = 'ERRO DE LIGACAO com o painel: HTTP %s',
    ['auth_connection2']   = 'Verifique a sua internet e tente novamente.',
    ['auth_connection3']   = 'Se o problema persistir, contacte math0001 no Discord.',
    ['auth_shutdown']      = 'Resource desativado por falha de autenticacao.',
}

-- ==================== THAI ====================
Locales['th'] = {
    -- Wings
    ['wings_equipped']     = 'สวมปีกแล้ว! (สี %s)',
    ['wings_removed']      = 'ถอดปีกแล้ว',
    ['wings_failed']       = 'สร้างปีกล้มเหลว',
    ['no_permission']      = 'ไม่มีสิทธิ์',
    ['invalid_color']      = 'สีไม่ถูกต้อง (1-%s)',
    ['flight_equip_first'] = 'สวมปีกก่อน! (/%s)',
    ['massive_cleanup']    = 'ลบปีกแล้ว %s ชิ้น',
    ['color_changed']      = 'เปลี่ยนสีปีกเป็น %s',
    ['loading']            = 'กำลังโหลด...',
    ['keybind_toggle']     = 'เปิด/ปิด ปีก',
    ['keybind_fly']        = 'เปิด/ปิด การบิน',
    ['keybind_hud']        = 'เปิด/ปิด HUD Demon',
    -- Tail
    ['tail_equipped']      = 'สวมหางแล้ว! (สี %s)',
    ['tail_removed']       = 'ถอดหางแล้ว',
    ['tail_failed']        = 'สร้างหางล้มเหลว',
    ['tail_invalid_color'] = 'สีหางไม่ถูกต้อง (1-%s)',
    ['tail_color_changed'] = 'เปลี่ยนสีหางเป็น %s',
    ['tail_locked']        = 'คุณไม่สามารถสวมหางได้ในตอนนี้',
    -- Permissions / Cooldowns
    ['wings_locked']       = 'คุณไม่สามารถสวมปีกได้ในตอนนี้',
    ['cooldown_wait']      = 'รอ %s วินาทีก่อนใช้อีกครั้ง',
    -- Auth
    ['auth_no_key']        = 'ข้อผิดพลาด: ไม่มี key ใน server.cfg!',
    ['auth_add_line']      = 'เพิ่มบรรทัดต่อไปนี้ใน server.cfg ของคุณ:',
    ['auth_replace']       = 'แทนที่ AP-XXXX-XXXX-XXXX ด้วย key ที่ได้รับจากการซื้อ',
    ['auth_contact']       = 'ติดต่อ: math0001 บน Discord เพื่อขอความช่วยเหลือ',
    ['auth_not_found']     = 'KEY ที่ป้อนไม่มีอยู่ในระบบ',
    ['auth_check_cfg']     = 'ตรวจสอบว่าพิมพ์ถูกต้องใน server.cfg',
    ['auth_format']        = 'รูปแบบ: set %s "AP-XXXX-XXXX-XXXX"',
    ['auth_disabled']      = 'KEY ของคุณถูกบล็อกและคุณสูญเสียการเข้าถึงผลิตภัณฑ์',
    ['auth_disabled_reason'] = 'อาจเกิดจากการละเมิดข้อกำหนดหรือการขอคืนเงิน',
    ['auth_disabled_contact'] = 'ติดต่อ math0001 บน Discord เพื่อขอข้อมูลเพิ่มเติม',
    ['auth_wrong_product'] = 'KEY นี้เป็นของผลิตภัณฑ์อื่น ไม่ใช่ Demon V3',
    ['auth_wrong_product2'] = 'แต่ละผลิตภัณฑ์มี key เฉพาะ ตรวจสอบในแผงควบคุม',
    ['auth_connection']    = 'ข้อผิดพลาดการเชื่อมต่อกับแผงควบคุม: HTTP %s',
    ['auth_connection2']   = 'ตรวจสอบอินเทอร์เน็ตแล้วลองอีกครั้ง',
    ['auth_connection3']   = 'หากปัญหายังคงอยู่ ติดต่อ math0001 บน Discord',
    ['auth_shutdown']      = 'Resource ถูกปิดใช้งานเนื่องจากการยืนยันตัวตนล้มเหลว',
}


--- Get localized string with optional format arguments
--- @param key string
--- @param ... any
--- @return string
function L(key, ...)
    local locale = Config.Locale or 'pt-BR'
    local text = Locales[locale] and Locales[locale][key] or Locales['en-US'][key] or Locales['pt-BR'][key] or key
    if ... then
        return string.format(text, ...)
    end
    return text
end

