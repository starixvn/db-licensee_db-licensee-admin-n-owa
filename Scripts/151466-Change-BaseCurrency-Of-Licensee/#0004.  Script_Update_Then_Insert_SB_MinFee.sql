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

PRINT 'Prepare new SB MinFee settings here: 999 records'
BEGIN
	INSERT INTO @SB_MinFeeSettings(PartyId, PartyName, FeeAmount, MinFeeTerm, FromDate, ToDate)
	VALUES(14, '12Bet', 40000, 'new term...', '20210301', '20500101')
		 ,(72, '9Club', 50000, 'new term2...', '20210301', '20500101')
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