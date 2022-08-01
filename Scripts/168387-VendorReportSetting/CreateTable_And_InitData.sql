/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20220316@Danny
	DB: DBCUST.bodb_licensee
	Description: Create table structure And Initialize data
*/
GO
-- DROP TABLE LA_VendorPaymentSetting
CREATE TABLE [dbo].[LA_VendorPaymentSetting](
	ProductId								INT				NOT NULL,
	ReportFunctionKey						NVARCHAR(50)	NULL,
	TemplateID								SMALLINT		NULL,
	TimezoneIDs								VARCHAR(50)		NULL,
	IsConvertNegativeFeeToZero				BIT				NULL,
	IsConvertNegativePaytoSupplierToZero	BIT				NULL,
	IsActive								BIT				NULL,
	 CONSTRAINT [PK_LA_VendorPaymentSetting] PRIMARY KEY CLUSTERED 
	(
		[Productid] ASC
	)
)

INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (2, 'VendorPaymentInDetails_NG', 2, '1', 0, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (5, 'VendorPaymentInDetails_VS', 3, '1', 1, 1, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (8, 'VendorPaymentInDetails_KN', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (10, 'VendorPaymentInDetails_AGC', 15, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (21, 'VendorPaymentInDetails_AB', 9, '1,2', 0, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (22, 'VendorPaymentInDetails_VB', 13, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (27, 'VendorPaymentInDetails_VS2', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (28, 'VendorPaymentInDetails_LT', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (31, 'VendorPaymentInDetails_BX', 4, '1', 0, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (32, 'VendorPaymentInDetails_PP', 5, '1,0', 0, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (34, 'VendorPaymentInDetails_CC', 8, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (36, 'VendorPaymentInDetails_SG', 16, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (39, 'VendorPaymentInDetails_SAG', 10, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (40, 'VendorPaymentInDetails_TG', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (45, 'VendorPaymentInDetails_SXG', 6, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (46, 'VendorPaymentInDetails_IBCLC', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (47, 'VendorPaymentInDetails_BBIN', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (49, 'VendorPaymentInDetails_VS3', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (50, 'VendorPaymentInDetails_RNGW', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (51, 'VendorPaymentInDetails_WM', 1, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (52, 'VendorPaymentInDetails_ION', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (55, 'VendorPaymentInDetails_PGS', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (56, 'VendorPaymentInDetails_JK', 1, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (57, 'VendorPaymentInDetails_BGG', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (60, 'VendorPaymentInDetails_MXG', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (61, 'VendorPaymentInDetails_HB', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (62, 'VendorPaymentInDetails_CG', 1, '1,2', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (65, 'VendorPaymentInDetails_PPL', 14, '0,1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (67, 'VendorPaymentInDetails_AP', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (68, 'VendorPaymentInDetails_APM', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (69, 'VendorPaymentInDetails_BTC', 1, '1', 1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (70, 'VendorPaymentInDetails_FGGL', 7, '1,2',1, 0, 1)
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (1000, 'VendorPaymentInDetails_BetBuilder', 11, '1', 1, 0, 1) -- betBuilder
INSERT INTO LA_VendorPaymentSetting(Productid, ReportFunctionKey, TemplateID, TimezoneIDs, IsConvertNegativeFeeToZero, IsConvertNegativePaytoSupplierToZero, IsActive) VALUES (1001, 'VendorPaymentInDetails_MuayThai', 12, '1', 0, 0, 1) -- MuayThai
GO
