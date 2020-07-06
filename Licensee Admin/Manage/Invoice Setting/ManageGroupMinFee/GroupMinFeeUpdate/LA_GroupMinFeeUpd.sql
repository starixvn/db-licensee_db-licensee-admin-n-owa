/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeUpd]
	@GroupMinFeeID			SMALLINT,
	@GroupName				NVARCHAR(110),
	@FromDate				DATE,
	@ToDate					DATE,
	@LicenseeSettingData	VARCHAR(MAX),
	@GroupMinFeeSettingData	VARCHAR(MAX),
	@ErrCode				INT				= 0		OUTPUT, 
	@ErrMsg					VARCHAR(4000)	= ''	OUTPUT
AS
/*
	Created: 20200703@Happy
	Task : Update GroupMinFee
	DB: DBCUST.bodb_Licensee

	Revisions:

	Param's Explannation:
		@GroupMinFeeHeaderOldData = '<Root>
										<GroupMinFeeHeader>
											<GroupMinFeeID>1</GroupMinFeeID>
											<Name>Group_1</Name>
											<FromDate>20190108</FromDate>
											<ToDate>20500101</ToDate>
										</GroupMinFeeHeader>
									</Root>'
									
		@LicenseeSettingData = '<Root>
									<LicenseeSetting>
										<PartyID>1</PartyID>
										<IsPrimary>1</IsPrimary>
									</LicenseeSetting>
									<LicenseeSetting>
										<PartyID>2</PartyID>
										<IsPrimary>0</IsPrimary>
									</LicenseeSetting>
								</Root>'
		
		@GroupMinFeeSettingData = '<Root>
										<GroupMinFeeSetting>
											<ProductId>0</ProductId>
											<MinimumFee>5000</MinimumFee>
											<MinFeeTerms>EUR 5,000 (Waived for the first 3 months after launched)</MinFeeTerms>
											<CurrencyId>6</CurrencyId>
											<FromDate>20190108</FromDate>
											<ToDate>20500101</ToDate>
										</GroupMinFeeSetting>
										<GroupMinFeeSetting>
											<ProductId>0</ProductId>
											<MinimumFee>2</MinimumFee>
											<MinFeeTerms></MinFeeTerms>
											<CurrencyId>6</CurrencyId>
											<FromDate>20190108</FromDate>
											<ToDate>20190407</ToDate>
										</GroupMinFeeSetting>
									</Root>'
*/
BEGIN
	SET NOCOUNT ON;
	DECLARE @HeaderOldData XML,
			@AssignmentOldData XML,
			@DetailOldData XML
	--#Region update LA_GroupMinFeeHeader
	EXEC dbo.LA_GroupMinFeeHeaderUpd @GroupMinFeeID, @GroupName, @FromDate, @ToDate, @HeaderOldData OUTPUT, @ErrCode OUTPUT, @ErrMsg OUTPUT
	--#Endregion
	
	--#Region update LA_GroupMinFeeAssignment
	IF ISNULL(@ErrCode, 0) = 0
	BEGIN
		EXEC dbo.LA_GroupMinFeeAssignmentUpd @GroupMinFeeID, @LicenseeSettingData, @AssignmentOldData OUTPUT, @ErrCode OUTPUT, @ErrMsg OUTPUT  
	END
	--#Endregion
	
	--#Region update LA_GroupMinFeeDetail
	IF ISNULL(@ErrCode, 0) = 0
	BEGIN
		EXEC dbo.LA_GroupMinFeeDetailUpd @GroupMinFeeID, @GroupMinFeeSettingData, @DetailOldData OUTPUT, @ErrCode OUTPUT, @ErrMsg OUTPUT  
	END
	--#Endregion
	
	IF @ErrCode <> 0
	BEGIN
		EXEC dbo.LA_GroupMinFeeUpd_RollBack @GroupMinFeeID, @HeaderOldData, @AssignmentOldData, @DetailOldData, @ErrCode OUTPUT, @ErrMsg OUTPUT
		RETURN
	END
END
GO
