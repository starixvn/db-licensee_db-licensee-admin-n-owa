/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210317@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: End Sportsbook min feee settings & create a new one with a different amount
*/
USE bodb_Licensee 
GO

DECLARE @CutOffTime DATE = '20210301',
		@MinFeeTypeId	INT = 1,
		@CNY_CurrencyId INT = 13

DECLARE @SB_MinFeeSettings	TABLE (PartyID INT, PartyName VARCHAR(50), FeeAmount MONEY,  MinFeeTerm NVARCHAR(1000), FromDate DATE, ToDate DATE, Current_SB_MinFeeID INT) 

PRINT 'Prepare new SB MinFee settings here: 66 records'
BEGIN
	INSERT INTO @SB_MinFeeSettings(PartyId, PartyName, FeeAmount, MinFeeTerm, FromDate, ToDate)
	VALUES(342, '18Luck', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(415, 	'24AVIA', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(158, 	'365online', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(60, 	'88Macao', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(482, 	'9dianyule', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(124, 	'Abcasino', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(68, 	'AG', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(391, 	'allwincity', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(326, 	'ANGbet', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(487, 	'Baolong', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20210310')
		,(346, 	'Bobbet', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(43, 	'Boma365', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(218, 	'Boying', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(462, 	'Bsdbet', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(331, 	'Callmeboss', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(367, 	'Champion', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(428, 	'Datang001', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(244, 	'Dawoo', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(273, 	'e8casino', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(247, 	'FLC', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(517, 	'FYyule', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(168, 	'Gampag', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(358, 	'Gaobet', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(337, 	'gbkj', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(395, 	'GESAB', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(441, 	'HBO999', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(481, 	'HC6YAYOU', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(258, 	'Heaven', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(127, 	'Hecbet', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(49, 	'Happy1668', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(509, 	'Hejiyongle', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(424, 	'hjccasino', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(71, 	'HONBET', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(87, 	'HonorW', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(169, 	'HuangMa', 	0, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为0人民币', 	'20210301', 	'20500101')
		,(489, 	'J9YAYOU', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(320, 	'JIBET', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(501, 	'Junbet', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(446, 	'JZFortune', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(479, 	'liv66', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(529, 	'liv66SW', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(52, 	'KeenOcean', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(537, 	'livv88sw', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(355, 	'MARS', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(162, 	'Mayayule', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(488, 	'Mayibet', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(96, 	'Newhonbet', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(47, 	'OLE777', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(361, 	'Onegaming', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(460, 	'OneSports', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(282, 	'OPEBet', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(513, 	'OSUSDT', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(516, 	'PKKing', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(468, 	'Soon88', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(432, 	'Tianbo', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(438, 	'TYCgame', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(480, 	'US8YAYOU', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(359, 	'UwinY', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(228, 	'VCBA', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(348, 	'VWIN66', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(299, 	'WBS', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(531, 	'win365', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(379, 	'WKCUR', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(380, 	'WKPHIL', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
		,(308, 	'Xinbo', 	40000, 	N'从2021年3月1日起，帐单改为人民币计价，保底费为40,000人民币', 	'20210301', 	'20500101')
		,(303, 	'Yibo', 	40000, 	N'wef 1 Mar 2021, billing is in CNY currency, minimum fees is equiv to CNY40,000', 	'20210301', 	'20500101')
END

PRINT 'Step 1. Find exactly Current_SB_MinFeeID'
BEGIN
	UPDATE p
	SET	p.Current_SB_MinFeeID = m2.MinFeeId
	FROM @SB_MinFeeSettings p
	CROSS APPLY
	(
		SELECT TOP 1 m.MinFeeId
		FROM LA_MinFee m WITH(NOLOCK)
		WHERE m.ToDate >= @CutOffTime AND m.PartyId = p.PartyID AND m.FeeTypeId = @MinFeeTypeId AND m.ProductID = 0 -- SB only
		ORDER BY ToDate DESC
	) m2
END

PRINT 'Step 2. End current SB MinFee settings'
BEGIN
	UPDATE m
	SET m.ToDate = DATEADD(DAY, -1, p.FromDate) 
	FROM LA_MinFee m WITH (NOLOCK)
	INNER JOIN @SB_MinFeeSettings p ON m.MinFeeId = p.Current_SB_MinFeeID
END

PRINT 'Step 3. Add new SB MinFee settings with a different amount'
BEGIN
	INSERT INTO dbo.LA_MinFee(PartyId, ProductId, FeeTypeId, FeeAmount, FromDate, ToDate, MinFeeTerm, [Priority], CurrencyId, MonthOfDeduction)
	SELECT new.PartyID, old.ProductId, FeeTypeId, new.FeeAmount, new.FromDate, new.ToDate, old.MinFeeTerm + CHAR(13) + new.MinFeeTerm, [Priority], @CNY_CurrencyId, old.MonthOfDeduction
	FROM @SB_MinFeeSettings new
	INNER JOIN LA_MinFee old WITH(NOLOCK) ON new.Current_SB_MinFeeID = old.MinFeeId
END