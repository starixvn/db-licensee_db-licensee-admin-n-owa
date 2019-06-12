USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_MinFeeValidate] 
	@MinfeeId		INT					= 0 
	, @PayerIdList	VARCHAR(4000)		= ''
	, @Mode			VARCHAR(10)			= 'R'
	, @ErrCode		INT					= 0		OUTPUT
	, @ErrMsg		VARCHAR(4000)		= ''	OUTPUT
AS
/*  
	 Created: 20150504@Florent
	 Task : Validate list of Payers have applied to billing Invoice yet
	 DB: DB052.bodb_Licensee
	 Revisions:     
		
	 Params:
		+ @@MinfeeId : = 0 check all Minfee info of Party
		+ @Mode : 
			- R: Remove, A: Add
*/
BEGIN
	SET NOCOUNT ON
	RETURN --TODO: when implement Invoice page
	IF ISNULL(@PayerIdList , '') = '' OR ISNULL(@MinfeeId, 0) = 0
		RETURN

	DECLARE @PayerNameList VARCHAR(4000)
	
	DECLARE @Minfee AS TABLE (MinFeeId INT, PartyId INT, ProductId INT, FeeType INT, FromDate DATE, ToDate DATE)		

	INSERT INTO @Minfee(MinFeeId, PartyId, FeeType, ProductId, FromDate, ToDate)
	SELECT MinFeeId, PartyID, FeeTypeId, ProductId, FromDate, ToDate 
	FROM dbo.LA_MinFee WITH (NOLOCK)		
	WHERE (@MinFeeId = 0 OR (@MinFeeId <> 0 AND MinFeeId = @MinFeeId))

	IF NOT EXISTS (SELECT 1 FROM @Minfee)
	BEGIN
		SELECT @ErrMsg = 'Delete failed. Please try again.', @ErrCode = 810
		RETURN
	END

	IF @Mode = 'R'
	BEGIN
		SET @PayerNameList = NULL

		-- check charge rate billing yet, depend fromdate todate of charge and date of invoice
		SELECT COALESCE(@PayerNameList + ',' + '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + ''''
						, '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + '''')
		FROM @Minfee a 			
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON a.PartyId = p.PartyID
			INNER JOIN dbo.OAS_PartyDetail pp WITH (NOLOCK) ON p.PartyID = pp.PartyID
			--INNER JOIN dbo.LA_InvoiceHeader inv WITH(NOLOCK) ON p.PartyId = inv.PartyId  --> todo
		WHERE a.PartyId IN (SELECT val FROM strSplit(@PayerIdList, ','))
			--AND inv.Invdate BETWEEN a.FromDate AND a.ToDate			

		IF ISNULL(@PayerNameList , '') = ''
		BEGIN
			SELECT @ErrMsg = 'Infomation of Minfee rate cannot remove, please try again.', @ErrCode = 811
			RETURN
		END
	END
	
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_MinFeeValidate] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_MinFeeValidate] TO bodbAdminNet
