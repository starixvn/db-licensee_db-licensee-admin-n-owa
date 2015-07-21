USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_PayerGroupValidatePayerAssignment] 
	@PayerGroupId		INT
	, @PayerIdList		VARCHAR(4000)	= ''
	, @Mode				VARCHAR(10)		= 'R'
	, @ErrCode			INT				= 0		OUTPUT
	, @ErrMsg			VARCHAR(4000)	= ''	OUTPUT
AS
/*  
	 Created: 20150423@Florent
	 Task : Validate list of Payers have applied to billing Invoice yet
	 DB: DB052.bodb_Licensee
	 Revisions:     
		
	 Params:
		+ @Mode : 
			- R: Remove, A: Add
*/
BEGIN
	SET NOCOUNT ON
	
	IF ISNULL(@PayerIdList , '') = '' OR ISNULL(@PayerGroupId, 0) = 0
		RETURN

	DECLARE @PayerNameList VARCHAR(4000), @DiscountType TINYINT
	
	IF @Mode = 'A'
	BEGIN
		-- check exists
		IF EXISTS (SELECT 1 FROM dbo.LA_PartyGroupAssignment a WITH (NOLOCK) WHERE a.PartyId IN (SELECT val FROM strSplit(@PayerIdList, ',')))
			BEGIN
				SELECT @PayerNameList = COALESCE(@PayerNameList + ',' + '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + ''''
						, '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + '''')
				FROM dbo.LA_PartyGroupAssignment a WITH(NOLOCK)					
					INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON a.PartyID = p.PartyID
					INNER JOIN dbo.OAS_PartyDetail pp WITH(NOLOCK) ON a.PartyID = pp.PartyID
					--INNER JOIN dbo.LA_InvoiceHeader inv WITH(NOLOCK) ON p.PartyId = inv.PartyId  --> todo
				WHERE a.PartyId IN (SELECT val FROM strSplit(@PayerIdList, ','))

				SELECT @ErrMsg = 'Payer ' + @PayerNameList + ' cannot be add to the payer group, it is being applied!' , @ErrCode = 205					
				RETURN
			END
	END
	RETURN --TODO: when implement Invoice page
	IF @Mode = 'R'
	BEGIN
		SET @PayerNameList = NULL

		SELECT COALESCE(@PayerNameList + ',' + '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + ''''
						, '''' + CASE WHEN ISNULL(pp.BrandName, '') = '' THEN ISNULL(p.PartyName, '') ELSE ISNULL(pp.BrandName, '') END + '''')
		FROM dbo.LA_PartyGroupAssignment a WITH(NOLOCK)
			INNER JOIN dbo.LA_PartyGroup h WITH(NOLOCK) ON a.PartyGroupId = h.PartyGroupId
			INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON a.PartyID = p.PartyID
			INNER JOIN dbo.OAS_PartyDetail pp WITH(NOLOCK) ON a.PartyID = pp.PartyID
			--INNER JOIN dbo.LA_InvoiceHeader inv WITH(NOLOCK) ON p.PartyId = inv.PartyId  --> todo
		WHERE h.PartyGroupId = @PayerGroupId
			AND a.PartyId IN (SELECT val FROM strSplit(@PayerIdList, ','))
		IF ISNULL(@PayerNameList , '') = ''
		BEGIN
			SELECT @ErrMsg = 'Payer ' + @PayerNameList + ' cannot be removed out of the payer group, it is being applied!' , @ErrCode = 204
			RETURN
		END
	END
	
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_PayerGroupValidatePayerAssignment] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_PayerGroupValidatePayerAssignment] TO bodbAdminNet 
