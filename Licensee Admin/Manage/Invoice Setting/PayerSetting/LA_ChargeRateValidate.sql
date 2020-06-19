/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_ChargeRateValidate] 
	@ChargeId		INT					= 0
	, @PayerIdList	VARCHAR(4000)		= ''
	, @Mode			VARCHAR(10)			= 'R'
	, @ErrCode		INT					= 0 OUTPUT
	, @ErrMsg		VARCHAR(4000)		= '' OUTPUT
AS
/*  
	 Created: 20150504@Florent
	 Task : Validate list of Payers have applied to billing Invoice yet
	 DB: DB052.bodb_Licensee
	 Revisions:     
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20200619@Happy: Increase the length of @ProductCode params [#128570]
	 Params:
		+ @ChargeId : = 0 check all charge infor of Party
		+ @Mode : 
			- R: Remove, A: Add
*/
BEGIN
	SET NOCOUNT ON
	RETURN --TODO: when implement Invoice page
	IF ISNULL(@PayerIdList , '') = '' OR ISNULL(@ChargeId, 0) = 0
		RETURN

	DECLARE @PayerNameList VARCHAR(4000), @ProductListAll VARCHAR(500) = '', @MinDate DATE , @MaxDate DATE
	
	DECLARE @ChargeRate AS TABLE (ChargeId INT, PartyId INT, ProductId INT, FromDate DATE, ToDate DATE)	
	--get list Product
	SELECT @ProductListAll = @ProductListAll + ProductPrefix + ','
	FROM dbo.LA_f_Products3rd('')
	SET @ProductListAll = REPLACE(SUBSTRING(@ProductListAll, 0, LEN(@ProductListAll)), 'RB', '')

	--get Minium date, maximum date
	SELECT @MinDate = MIN(ci.FromDate)
		, @MaxDate = MAX(ci.ToDate)
	FROM dbo.OAS_ChargeInfo ci WITH (NOLOCK)
		INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2

	INSERT INTO @ChargeRate(ChargeID, PartyId, ProductId, FromDate, ToDate)
	SELECT ChargeID, PartyID, ProductId, FromDate, ToDate 
	FROM dbo.LA_f_ChargeInfo(@PayerIdList, @MinDate, @MaxDate ,@ProductListAll, 'OA', 1)		
	WHERE (@ChargeId = 0 OR (@ChargeId <> 0 AND ChargeID = @ChargeId))

	IF NOT EXISTS (SELECT 1 FROM @ChargeRate)
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 710
		RETURN
	END

	IF @Mode = 'R'
	BEGIN
		SET @PayerNameList = NULL

		-- check charge rate billing yet, depend fromdate todate of charge and date of invoice
		SELECT COALESCE(@PayerNameList + ',' + '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + ''''
						, '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + '''')
		FROM @ChargeRate a 			
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON a.PartyId = p.PartyID
			INNER JOIN dbo.OAS_PartyDetail pp WITH (NOLOCK) ON p.PartyID = pp.PartyID
			--INNER JOIN dbo.LA_InvoiceHeader inv WITH(NOLOCK) ON p.PartyId = inv.PartyId  --> todo
		WHERE a.PartyId IN (SELECT val FROM strSplit(@PayerIdList, ','))
			--AND inv.Invdate BETWEEN a.FromDate AND a.ToDate
			

		IF ISNULL(@PayerNameList , '') = ''
		BEGIN
			SELECT @ErrMsg = 'Infomation of charge rate cannot remove, please try again', @ErrCode = 711
			RETURN
		END
	END
	
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_ChargeRateValidate] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_ChargeRateValidate] TO bodbAdminNet
GO
