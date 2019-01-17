/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_LaunchLicensee_MinFeeIns]
	@PartyId			INT,
	@BaseCurrencyId		TINYINT,
	@MinFeeSettingData	VARCHAR(MAX),
	@ErrCode			INT				= 0		OUTPUT, 
	@ErrMsg				VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20190107@Parsons
	Task : Launch new licensee
	DB: DB052.bodb_Licensee

	Revisions:
	- 20190107@Parsons: Launch new licensee

	Param's Explannation: 
						@MinFeeSettingData = '<Root>
							<MinFeeSetting>
								<ProductId>0</ProductId>
								<FeeTypeId>1</FeeTypeId>
								<FeeAmount>5000</FeeAmount>
								<BaseCurrencyID>6</BaseCurrencyID>
								<FromDate>20190108</FromDate>
								<ToDate>20500101</ToDate>
								<MinFeeTerm>EUR 5,000 (Waived for the first 3 months after launched)</MinFeeTerm>
								<Priority>1</Priority>
							</MinFeeSetting>
							<MinFeeSetting>
								<ProductId>0</ProductId>
								<FeeTypeId>2</FeeTypeId>
								<FeeAmount></FeeAmount>
								<BaseCurrencyID>6</BaseCurrencyID>
								<FromDate>20190108</FromDate>
								<ToDate>20190407</ToDate>
								<MinFeeTerm></MinFeeTerm>
								<Priority>2</Priority>
							</MinFeeSetting>
						</Root>'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @MinFeeSettings	TABLE (ProductId TINYINT, FeeTypeId TINYINT, FeeAmount MONEY, FromDate DATE, ToDate DATE, MinFeeTerm NVARCHAR(1000), [Priority] TINYINT, BaseCurrencyID INT) 

	-- #Region MinFee
	IF(@MinFeeSettingData <> '')
	BEGIN
		DECLARE @docHandler INT

		BEGIN TRY
			EXEC sp_xml_preparedocument @docHandler OUTPUT, @MinFeeSettingData
			INSERT INTO @MinFeeSettings(ProductId, FeeTypeId, FeeAmount, FromDate, ToDate, MinFeeTerm, [Priority], BaseCurrencyID)
			SELECT ProductId, FeeTypeId, FeeAmount, FromDate, ToDate, MinFeeTerm, [Priority], BaseCurrencyID
			FROM OPENXML(@docHandler, 'Root/MinFeeSetting')
			WITH (ProductId	INT 'ProductId', 
					FeeTypeId	TINYINT 'FeeTypeId', 
					FeeAmount	MONEY 'FeeAmount', 
					FromDate	DATE 'FromDate',
					ToDate		DATE 'ToDate',
					MinFeeTerm	NVARCHAR(1000) 'MinFeeTerm',
					[Priority]	TINYINT 'Priority',
					BaseCurrencyID INT 'BaseCurrencyID')
	
			EXEC sp_xml_removedocument @docHandler
		END TRY
		BEGIN CATCH
			SELECT @ErrMsg = 'Minfee setting data invalid. Please try again.', @ErrCode = 100
			RETURN
		END CATCH;
	END

	INSERT INTO dbo.LA_MinFee(PartyId, ProductId, FeeTypeId, FeeAmount, FromDate, ToDate, MinFeeTerm, [Priority], CurrencyId)
	SELECT @PartyId, ProductId, FeeTypeId, FeeAmount, FromDate, ToDate, MinFeeTerm, [Priority], BaseCurrencyID  
	FROM @MinFeeSettings
	
	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Insert LA_MinFee failed. Please try again.', @ErrCode =  503
		RETURN
	END
			
	-- Caculate Month of Deduction
	DECLARE @AMF MONEY
	SELECT @AMF = SUM(ISNULL(d.Income, 0))
	FROM dbo.LA_InvoiceHeader h WITH (NOLOCK)
		INNER JOIN dbo.LA_InvoiceStatement d WITH (NOLOCK) ON h.InvoiceHeaderId = d.InvoiceHeaderId
	WHERE h.InvoiceType = 7 AND d.InvItemTypeId = 3 AND h.StatusId = 0 AND h.Environment = 'PRO'					
	AND h.PartyId = @PartyId
	AND h.CurrencyId = @BaseCurrencyId

	IF ISNULL(@AMF, 0) <> 0
	BEGIN
		UPDATE m
		SET m.MonthOfDeduction = CEILING(@AMF / ISNULL(m.FeeAmount, 0))
		FROM  dbo.LA_MinFee m WITH(NOLOCK)
		INNER JOIN @MinFeeSettings ms ON m.PartyId = @PartyID  
		WHERE m.FeeTypeId = 1 AND m.ProductId = 0

		IF @@ERROR <> 0
		BEGIN
			SELECT @ErrMsg = 'Update LA_MinFee failed. Please try again.', @ErrCode =  504
			RETURN
		END
	END
	-- #Endregion MinFee
END
GO