USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_FunctionPartiesPermission]
	@PartyId	INT,
	@ProductId	INT
AS
/*	Header:
	Created: 20170221@Bruce
	Task : #70050: Add function permission for licensee
	DB: DB052.bodb_Licensee
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @FunctionKeys TABLE (FunctionKey VARCHAR(100))
	DECLARE @ProductCode VARCHAR(10) = (SELECT ProductPrefix FROM dbo.LA_f_Products3rd('') WHERE ProductId=@ProductId)

	IF @ProductCode IN ('SB','BA','NG','LC','CS','VS','VB','KN','AGC','GD','VG','MGCLC','MGCRNG')
	INSERT INTO @FunctionKeys VALUES 
		('LicenseePerformance'),
		('LicenseeWinLoss'),
		('CurrencyWinLossReport'),
		('LicenseePerformanceDetail'),
		('LicenseePerformancebyTurnOver'),
		('LicenseePerformancebyLicensingFee'),
		('LicenseePerformancebyMargin')

	IF @ProductCode = 'NG'
	INSERT INTO @FunctionKeys VALUES ('NumberGameReport')

	IF @ProductCode = 'LC'
	INSERT INTO @FunctionKeys VALUES ('LiveCasinoReport')

	IF @ProductCode = 'VS'
	INSERT INTO @FunctionKeys VALUES ('VirtualSportsReport')

	IF @ProductCode IN ('KN','AGC','GD','VG','MGCLC','MGCRNG')
	DELETE @FunctionKeys WHERE FunctionKey NOT IN ('LicenseeWinLoss','LicenseePerformanceDetail')

	IF @ProductCode = 'KN'
	INSERT INTO @FunctionKeys VALUES ('NewKenoReport'),('KenoReport')

	IF @ProductCode = 'AGC'
	INSERT INTO @FunctionKeys VALUES ('AGCasinoReport')

	IF @ProductCode = 'GD'
	INSERT INTO @FunctionKeys VALUES ('GoldDeluxeReport')

	IF @ProductCode IN ('MGCLC','MGCRNG')
	INSERT INTO @FunctionKeys VALUES ('MicrogamingFourReport'),('MicrogamingZeroReport')

	IF @ProductCode IN ('BT','CB','AB','NG2','FW')
	DELETE @FunctionKeys

	IF @ProductCode = 'BT'
	INSERT INTO @FunctionKeys VALUES ('BetTradeReport')

	IF @ProductCode = 'CB'
	INSERT INTO @FunctionKeys VALUES ('ColossusBetReport')

	IF @ProductCode = 'AB'
	INSERT INTO @FunctionKeys VALUES ('AllBetWinLossGMT8')

	IF @ProductCode = 'NG2'
	INSERT INTO @FunctionKeys VALUES ('Ng2WinLoss')

	IF @ProductCode = 'FW'
	INSERT INTO @FunctionKeys VALUES ('FishingWorldWinLoss')

	INSERT INTO dbo.LA_FunctionParty(FunctionID, PartyID)
	SELECT f.FunctionID, @PartyId
	FROM dbo.LA_Function f WITH(NOLOCK)
	WHERE EXISTS (SELECT 1 FROM @FunctionKeys fk WHERE fk.FunctionKey = f.FunctionKey) AND
		NOT EXISTS (SELECT 1 FROM dbo.LA_FunctionParty fp WITH(NOLOCK) WHERE PartyID = @PartyId AND fp.FunctionID=f.FunctionID)
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_FunctionPartiesPermission] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_FunctionPartiesPermission] TO bodbAdminNet
GO