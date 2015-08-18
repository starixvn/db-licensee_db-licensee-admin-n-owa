USE [bodb_Licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Inv_InvoiceAmountGenerate]   Script Date: 07/20/2015 09:12:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_AutoMail_LicenseeWinLossByProduct]	  
	@FromDate		DATETIME,
	@ToDate			DATETIME,	
	@ErrCode		INT				= 0		OUTPUT,
	@ErrMsg			NVARCHAR(1000)	= ''	OUTPUT,
	@BaseCurrency	INT				=		OUTPUT
WITH RECOMPILE
AS
/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_Licensee
   
	Revisions: 
		+ 2015.08.06: Invoice Amount - Generate
*/
/*	Example:
	USE bodb_Licensee
	DECLARE @FromDate DATETIME,
		@ToDate DATETIME,
		@PartyId INT,
		@ProductCode VARCHAR(100),
		@ErrCode INT,
		@ErrMsg NVARCHAR(1000),
		@BaseCurrency NVARCHAR(20)
	SET @FromDate = '2015-07-1'
	SET @ToDate = '2015-07-31'
	SET @PartyId=17
	SET @ProductCode='SB,BA,RB,NG,LC,VS,CS,BG,KN,PTCS,AGC,GD,VG,BT,MGC'	
	
	EXEC [LA_Inv_InvoiceAmountGenerate] @PartyId, @FromDate, @ToDate, @ProductCode, @ErrCode OUT, @ErrMsg OUT, @BaseCurrency OUT
	SELECT @ErrCode, @ErrMsg, @BaseCurrency
*/
BEGIN
	SET NOCOUNT ON
	
	-- Region: Get party charge rate info
	DECLARE	@PartyIdString VARCHAR(100)
	SELECT	@PartyIdString = COALESCE(@PartyIdString + ', ', '') + CONVERT(VARCHAR(10), PartyId)
	FROM	@PartyGroup 
	
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
		FROM	dbo.LA_f_ChargeInfo(@PartyIdString, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)
		
	-- End region
	
END

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceAmountGenerate] TO bodbAdminNet