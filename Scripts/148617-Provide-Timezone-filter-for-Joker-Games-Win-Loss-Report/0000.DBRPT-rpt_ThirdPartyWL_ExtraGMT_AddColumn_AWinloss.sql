/*<info serverAlias="DBRPT-bodb_report"></info>*/
/*   
	Creator: 20210113@Parsons
	Task:   Add new column AWinloss [#FeatureID 148617]
	DB:	    DBRPT-bodb_report
	Remark:	Add new column AWinloss into DBRPT-bodb_report.rpt_ThirdPartyWL_ExtraGMT
*/

USE bodb_report
GO

ALTER TABLE dbo.rpt_ThirdPartyWL_ExtraGMT
	ADD AWinloss MONEY CONSTRAINT DF_rpt_ThirdPartyWL_ExtraGMT_AWinloss DEFAULT ((0)) WITH VALUES
GO