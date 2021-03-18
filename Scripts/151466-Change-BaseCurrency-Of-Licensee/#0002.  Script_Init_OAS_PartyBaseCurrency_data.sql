/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210314@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: Script_Init_OAS_PartyBaseCurrency_data.
*/
USE bodb_Licensee 
GO

DECLARE @CutOffTime DATE = '20210301',
		@ToDate DATE = '2050-01-01',
		@CNY_CurrencyId INT = 13

PRINT 'Step 1: Old LicenseeCode settings: Move from OAS_PartyDetail to OAS_PartyBaseCurrency'
BEGIN
	INSERT INTO OAS_PartyBaseCurrency(PartyID, BaseCurrencyId, LicenseeCode, FromDate, ToDate)
	SELECT p.PartyID, ISNULL(BaseCurrencyId, 6) BaseCurrencyId, ISNULL(LicenseeCode, ''),  ci.LaunchedDate, @ToDate
	FROM OAS_Party p WITH (NOLOCK)
	INNER JOIN  OAS_PartyDetail d WITH (NOLOCK) ON p.PartyID = d.PartyID
	INNER JOIN 
	(
		 SELECT FromParty AS PartyID, MIN(FromDate) AS LaunchedDate
		 FROM OAS_ChargeInfo ci WITH(NOLOCK)
		 GROUP BY FromParty
	)ci ON p.PartyID = ci.PartyID
	WHERE p.PartyType IN (1,5) AND ISNULL(d.IsDeposit, 0) = 1
	ORDER by p.PartyID 
END

----------------------------------------------------------------------------------------------------------------------------
PRINT 'Prepare LicenseeCode SB terms: 89 records'
DECLARE @NewLicenseeCodeTable TABLE(PartyID INT, PartyName VARCHAR(50), LicenseeCode VARCHAR(50), FromDate DATE, ToDate DATE)
INSERT INTO @NewLicenseeCodeTable(PartyID, PartyName, LicenseeCode, FromDate, ToDate)
VALUES
		(342, 	'18Luck', 	'PHL-LSEE-18LUCK CNY', 	@CutOffTime, 	@ToDate)
		,(415, 	'24AVIA', 	'PHL-LSEE-24AVIA CNY', 	@CutOffTime, 	@ToDate)
		,(158, 	'365online', 	'PHL-LSEE-365ONLINE CNY', 	@CutOffTime, 	@ToDate)
		,(530, 	'7kplatform', 	'PHL-LSEE-7KPLATFORM CNY', 	@CutOffTime, 	@ToDate)
		,(260, 	'818Bet', 	'PHL-LSEE-818BET CNY', 	@CutOffTime, 	@ToDate)
		,(60, 	'88MACAO', 	'PHL-LSEE-88MACAO CNY', 	@CutOffTime, 	@ToDate)
		,(482, 	'9dianyule', 	'PHL-LSEE-9DIANYULE CNY', 	@CutOffTime, 	@ToDate)
		,(124, 	'ABCASINO', 	'PHL-LSEE-ABCASINO CNY', 	@CutOffTime, 	@ToDate)
		,(68, 	'AG', 	'PHL-LSEE-AG CNY', 	@CutOffTime, 	@ToDate)
		,(391, 	'allwincity', 	'PHL-LSEE-ALLWINCITY CNY', 	@CutOffTime, 	@ToDate)
		,(326, 	'ANGbet', 	'PHL-LSEE-ANGBET CNY', 	@CutOffTime, 	@ToDate)
		,(377, 	'AnvoFH', 	'PHL-LSEE-ANVOFH CNY', 	@CutOffTime, 	@ToDate)
		,(487, 	'Baolong', 	'PHL-LSEE-BAOLONG CNY', 	@CutOffTime, 	@ToDate)
		,(319, 	'BETSUN', 	'PHL-LSEE-BETSUN CNY', 	@CutOffTime, 	@ToDate)
		,(220, 	'BigGaming', 	'PHL-LSEE-BIGGAMING CNY', 	@CutOffTime, 	@ToDate)
		,(43, 	'BOMA365', 	'PHL-LSEE-BOMA365 CNY', 	@CutOffTime, 	@ToDate)
		,(218, 	'Boying', 	'PHL-LSEE-BOYING CNY', 	@CutOffTime, 	@ToDate)
		,(462, 	'Bsdbet', 	'PHL-LSEE-BSDBET CNY', 	@CutOffTime, 	@ToDate)
		,(512, 	'BSSB168', 	'PHL-LSEE-BSSB168 CNY', 	@CutOffTime, 	@ToDate)
		,(427, 	'BWGaming', 	'PHL-LSEE-BWGAMING CNY', 	@CutOffTime, 	@ToDate)
		,(331, 	'Callmeboss', 	'PHL-LSEE-CALLMEBOSS CNY', 	@CutOffTime, 	@ToDate)
		,(310, 	'CGame', 	'PHL-LSEE-CGAME CNY', 	@CutOffTime, 	@ToDate)
		,(436, 	'CGame4', 	'PHL-LSEE-CGAME4 CNY', 	@CutOffTime, 	@ToDate)
		,(367, 	'Champion', 	'PHL-LSEE-CHAMPION CNY', 	@CutOffTime, 	@ToDate)
		,(428, 	'Datang001', 	'PHL-LSEE-DATANG001 CNY', 	@CutOffTime, 	@ToDate)
		,(244, 	'Dawoo', 	'PHL-LSEE-DAWOO CNY', 	@CutOffTime, 	@ToDate)
		,(273, 	'e8casino', 	'PHL-LSEE-E8CASINO CNY', 	@CutOffTime, 	@ToDate)
		,(419, 	'erhaozhan', 	'PHL-LSEE-ERHAOZHAN CNY', 	@CutOffTime, 	@ToDate)
		,(247, 	'FLC', 	'PHL-LSEE-FLC CNY', 	@CutOffTime, 	@ToDate)
		,(517, 	'FYyule', 	'PHL-LSEE-FYYULE CNY', 	@CutOffTime, 	@ToDate)
		,(495, 	'GAMEBee', 	'PHL-LSEE-GAMEBEE CNY', 	@CutOffTime, 	@ToDate)
		,(168, 	'Gampag', 	'PHL-LSEE-GAMPAG CNY', 	@CutOffTime, 	@ToDate)
		,(358, 	'Gaobet', 	'PHL-LSEE-GAOBET CNY', 	@CutOffTime, 	@ToDate)
		,(337, 	'gbkj', 	'PHL-LSEE-GBKJ CNY', 	@CutOffTime, 	@ToDate)
		,(395, 	'GESAB', 	'PHL-LSEE-GESAB CNY', 	@CutOffTime, 	@ToDate)
		,(441, 	'HBO999', 	'PHL-LSEE-HBO999 CNY', 	@CutOffTime, 	@ToDate)
		,(481, 	'HC6YAYOU', 	'PHL-LSEE-HC6YAYOU CNY', 	@CutOffTime, 	@ToDate)
		,(258, 	'Heaven', 	'PHL-LSEE-HEAVEN CNY', 	@CutOffTime, 	@ToDate)
		,(127, 	'HECBET', 	'PHL-LSEE-HECBET CNY', 	@CutOffTime, 	@ToDate)
		,(49, 	'HAPPY1668', 	'PHL-LSEE-HEJI CNY', 	@CutOffTime, 	@ToDate)
		,(509, 	'Hejiyongle', 	'PHL-LSEE-HEJIYONGLE CNY', 	@CutOffTime, 	@ToDate)
		,(424, 	'hjccasino', 	'PHL-LSEE-HJCCASINO CNY', 	@CutOffTime, 	@ToDate)
		,(71, 	'HONBET', 	'PHL-LSEE-HONBET CNY', 	@CutOffTime, 	@ToDate)
		,(87, 	'HONORW', 	'PHL-LSEE-HONORW CNY', 	@CutOffTime, 	@ToDate)
		,(169, 	'HuangMa', 	'PHL-LSEE-HUANGMA CNY', 	@CutOffTime, 	@ToDate)
		,(489, 	'J9YAYOU', 	'PHL-LSEE-J9YAYOU CNY', 	@CutOffTime, 	@ToDate)
		,(320, 	'JIBET', 	'PHL-LSEE-JIBET CNY', 	@CutOffTime, 	@ToDate)
		,(501, 	'Junbet', 	'PHL-LSEE-JUNBET CNY', 	@CutOffTime, 	@ToDate)
		,(446, 	'JZFortune', 	'PHL-LSEE-JZFORTUNE CNY', 	@CutOffTime, 	@ToDate)
		,(479, 	'liv66', 	'PHL-LSEE-LIV66 CNY', 	@CutOffTime, 	@ToDate)
		,(529, 	'liv66SW', 	'PHL-LSEE-LIV66SW CNY', 	@CutOffTime, 	@ToDate)
		,(52, 	'KEENOCEAN', 	'PHL-LSEE-LIVV88 CNY', 	@CutOffTime, 	@ToDate)
		,(537, 	'livv88sw', 	'PHL-LSEE-LIVV88SW CNY', 	@CutOffTime, 	@ToDate)
		,(355, 	'MARS', 	'PHL-LSEE-MARS CNY', 	@CutOffTime, 	@ToDate)
		,(162, 	'Mayayule', 	'PHL-LSEE-MAYAYULE CNY', 	@CutOffTime, 	@ToDate)
		,(488, 	'Mayibet', 	'PHL-LSEE-MAYIBET CNY', 	@CutOffTime, 	@ToDate)
		,(96, 	'NEWHONBET', 	'PHL-LSEE-NEWHONBET CNY', 	@CutOffTime, 	@ToDate)
		,(47, 	'OLE777', 	'PHL-LSEE-OLE Group CNY', 	@CutOffTime, 	@ToDate)
		,(361, 	'Onegaming', 	'PHL-LSEE-ONEGAMING CNY', 	@CutOffTime, 	@ToDate)
		,(282, 	'OPEbet', 	'PHL-LSEE-OPEBET CNY', 	@CutOffTime, 	@ToDate)
		,(356, 	'Pinbo', 	'PHL-LSEE-PINBO CNY', 	@CutOffTime, 	@ToDate)
		,(230, 	'PKbet', 	'PHL-LSEE-PKBET CNY', 	@CutOffTime, 	@ToDate)
		,(516, 	'PKKing', 	'PHL-LSEE-PKKING CNY', 	@CutOffTime, 	@ToDate)			
		,(543, 	'SDY', 	'PHL-LSEE-SDY CNY', 	@CutOffTime, 	@ToDate)
		,(468, 	'Soon88', 	'PHL-LSEE-SOON88 CNY', 	@CutOffTime, 	@ToDate)
		,(404, 	'Spark', 	'PHL-LSEE-SPARK CNY', 	@CutOffTime, 	@ToDate)
		,(306, 	'TangChao', 	'PHL-LSEE-TANGCHAO CNY', 	@CutOffTime, 	@ToDate)
		,(433, 	'TaoCai', 	'PHL-LSEE-TAOCAI CNY', 	@CutOffTime, 	@ToDate)
		,(430, 	'TCbet', 	'PHL-LSEE-TCBET CNY', 	@CutOffTime, 	@ToDate)
		,(151, 	'TGO', 	'PHL-LSEE-TGO CNY', 	@CutOffTime, 	@ToDate)
		,(500, 	'TSEnter', 	'PHL-LSEE-TSENTER CNY', 	@CutOffTime, 	@ToDate)
		,(438, 	'TYCgame', 	'PHL-LSEE-TYCGAME CNY', 	@CutOffTime, 	@ToDate)
		,(480, 	'US8YAYOU', 	'PHL-LSEE-US8YAYOU CNY', 	@CutOffTime, 	@ToDate)
		,(359, 	'UwinY', 	'PHL-LSEE-UWINY CNY', 	@CutOffTime, 	@ToDate)
		,(228, 	'VCBA', 	'PHL-LSEE-VCBA CNY', 	@CutOffTime, 	@ToDate)
		,(348, 	'VWIN66', 	'PHL-LSEE-VWIN66 CNY', 	@CutOffTime, 	@ToDate)
		,(299, 	'WBS', 	'PHL-LSEE-WBS CNY', 	@CutOffTime, 	@ToDate)
		,(531, 	'win365', 	'PHL-LSEE-WIN365 CNY', 	@CutOffTime, 	@ToDate)
		,(379, 	'WKCUR', 	'PHL-LSEE-WKCUR CNY', 	@CutOffTime, 	@ToDate)
		,(380, 	'WKPHIL', 	'PHL-LSEE-WKPHIL CNY', 	@CutOffTime, 	@ToDate)
		,(532, 	'wmcasino', 	'PHL-LSEE-WMCASINO CNY', 	@CutOffTime, 	@ToDate)
		,(308, 	'Xinbo', 	'PHL-LSEE-XINBO CNY', 	@CutOffTime, 	@ToDate)
		,(303, 	'Yibo', 	'PHL-LSEE-YIBO CNY', 	@CutOffTime, 	@ToDate)
		,(407, 	'YTX', 	'PHL-LSEE-YTX CNY', 	@CutOffTime, 	@ToDate)
		,(442, 	'Yunji', 	'PHL-LSEE-YUNJI CNY', 	@CutOffTime, 	@ToDate)
		,(460, 	'OneSports', 	'PHL-LSEE-ONESPORTS CNY', 	@CutOffTime, 	@ToDate)
		,(513, 	'OSUSDT', 	'PHL-LSEE-OSUSDT CNY', 	@CutOffTime, 	@ToDate)
		,(346, 	'Bobbet', 	'PHL-LSEE-BOBBET CNY', 	@CutOffTime, 	@ToDate)
		,(432, 	'Tianbo', 	'PHL-LSEE-TIANBO CNY', 	@CutOffTime, 	@ToDate)

PRINT 'Step 2: New LicenseeCode settings'
BEGIN
	PRINT 'Step 2.1: End old settings'
	UPDATE p
	SET ToDate = DATEADD(DAY, -1, @CutOffTime) 
	FROM @NewLicenseeCodeTable n
	INNER JOIN OAS_PartyBaseCurrency p WITH(NOLOCK) ON n.PartyID = p.PartyID

	PRINT 'Step 2.2: Add new settings'
	INSERT INTO OAS_PartyBaseCurrency(PartyID, BaseCurrencyId, LicenseeCode, FromDate, ToDate)
	SELECT PartyID, @CNY_CurrencyId, LicenseeCode, @CutOffTime, @ToDate
	FROM @NewLicenseeCodeTable
END