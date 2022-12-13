/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20221214@Danny
	DB: DBLIC.bodb_licenseeReport
	Description:  RUn ON DB053 Only
*/
GO

USE bodb_licenseeReport

CREATE TABLE #temp_list (PartyID INT, PartyName VARCHAR(50), BaseCurrencyName VARCHAR(10), ID INT identity(1,1), SiteID INT, WC_promo MONEY)
INSERT INTO  #temp_list (BaseCurrencyName, PartyName, WC_promo) VALUES
('CNY','JJBGAMECV',244356.033),
('EUR','TSLA',113919.9005),
('EUR','Macaubet',12943.497),
('EUR','ECLBET',43385.0534),
('EUR','KSTECH2',55602.3382),
('EUR','IONclub',53938.8584),
('CNY','JJBGAME',37686.353),
('EUR','Bobo88',6365.4617),
('CNY','LEIHUO',32130.317),
('CNY','OBGM',13677.889),
('EUR','SGM88',25788.1087),
('EUR','WINCLUB88',25464.1998),
('CNY','VKGAMECV',25301.139),
('CNY','GoldenF2',20296.952),
('CNY','GoldenF',16978.017),
('EUR','DFGame',16476.7072),
('CNY','ZFRT126CV',11029.272),
('EUR','LSM99',36638.487),
('EUR','INSERTGAME',5434.4195),
('EUR','Mybet88',730.2764),
('EUR','3star88',5120.6354),
('CNY','ZFRT126',4340.471),
('EUR','Aladdin99',2258.2754),
('EUR','TYgaming',8018.7596),
('CNY','ZFRT158CV',2134.292),
('CNY','DongYing',1620.919),
('EUR','Omni88',2523.415),
('CNY','HIDZ',5584.1007),
('CNY','bmwbet',3507.4112),
('CNY','ZFRT144CV',930.306),
('EUR','UGaming',861.6761),
('EUR','HBPT',2413.1471),
('EUR','WRSeamless',577.8875),
('EUR','Jiuyou',64.613),
('EUR','LG777',990.0684),
('EUR','HFYX',122.3798),
('EUR','0sServices',262.6832),
('EUR','De365',10.2343),
('EUR','IGSW',37.658),
('EUR','Barcelo9',4.1542)

UPDATE t
SET t.PartyID = op.PartyID,
	t.SiteID = l.LicenseeID
FROM #temp_list t
INNER JOIN bodb_licensee.dbo.OAS_Party op WITH(NOLOCK) ON  t.PartyName = op.PartyName
INNER JOIN bodb_licensee.dbo.Licensees l WITH(NOLOCK) ON op.OldRefID = l.LicenseeID

-- Update rpt_betting

--SELECT temp.*, t.WinLossA
--FROM	rpt_betting t WITH(ROWLOCK)
--INNER JOIN #temp_list temp ON t.SiteID = temp.SiteID
--WHERE	t.SiteID < 1000 AND t.rptDate = '2022-11-30' AND t.bettype = 17005


	UPDATE	t
	SET		t.WinLossA = temp.WC_promo
	FROM	rpt_betting t WITH(ROWLOCK)
	INNER JOIN #temp_list temp ON t.SiteID = temp.SiteID
	WHERE	t.SiteID < 1000 AND t.rptDate = '2022-11-30' AND t.bettype = 17005


-- Update rpt_bettingByProduct
	
--SELECT temp.*, t.GrossWL
--FROM	rpt_BettingByProduct t WITH(ROWLOCK)
--INNER JOIN #temp_list temp ON t.SiteID = temp.SiteID
--WHERE	t.SiteID < 1000 AND t.rptDate = '2022-11-30' AND t.bettype = 17005

	UPDATE	t
	SET		t.GrossWL = temp.WC_promo
	FROM	rpt_BettingByProduct t WITH(ROWLOCK)
	INNER JOIN #temp_list temp ON t.SiteID = temp.SiteID
	WHERE	t.SiteID < 1000 AND t.rptDate = '2022-11-30' AND t.bettype = 17005

DROP TABLE #temp_list
